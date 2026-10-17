"""Static checks on .github/workflows/testflight.yml (ported from Kazumi's test/ci). The
repo is public, so the workflow's logs and artifacts are too; these keep the signing
secrets out of both, and keep a dry run from ever uploading."""

import re
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/testflight.yml"
PINNED = re.compile(r"^[\w.-]+/[\w.-]+@[0-9a-f]{40}$")
LOCKED_INSTALL = "pip install --quiet --require-hashes -r scripts/testflight-requirements.txt"
# Also catches secrets['X'], toJSON(secrets) and `secrets: inherit`.
SECRET_REF = re.compile(r"\bsecrets\b")
UNCONDITIONAL = re.compile(r"always\(\)|failure\(\)|cancelled\(\)")
TRACING = r"set -\w*x|-o xtrace|\bbash -\w*x"


def live(run: str) -> str:
    """The script without comment lines, with continuation lines joined."""
    code = "\n".join(l for l in run.splitlines() if not l.lstrip().startswith("#"))
    return re.sub(r"\\\n\s*", " ", code)


class WorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text(encoding="utf-8")
        cls.doc = yaml.safe_load(cls.text)
        cls.jobs = cls.doc["jobs"]

    def steps(self, job=None):
        for job_name, spec in self.jobs.items():
            if job in (None, job_name):
                for step in spec.get("steps", []):
                    yield job_name, step

    def step(self, job, name):
        return next(s for _, s in self.steps(job) if s.get("name") == name)

    def test_only_started_by_hand(self):
        # PyYAML reads the bare key `on` as True.
        self.assertEqual({"workflow_dispatch"}, set(self.doc[True]))

    def test_uploading_must_be_asked_for(self):
        upload = self.doc[True]["workflow_dispatch"]["inputs"]["upload"]
        self.assertEqual((True, False), (upload["required"], upload["default"]))

    def test_token_is_read_only(self):
        self.assertEqual({"contents": "read"}, self.doc["permissions"])
        for name, job in self.jobs.items():
            self.assertNotIn("permissions", job, name)

    def test_actions_are_pinned_to_commits(self):
        for job, step in self.steps():
            if "uses" in step:
                self.assertRegex(step["uses"], PINNED, f"{job}: {step['uses']}")

    def test_no_shared_caches(self):
        # Enforced by the cache service for every step, not just flutter-action's.
        self.assertEqual("none", self.doc.get("cache-mode"))
        flutter = next(s for _, s in self.steps("build") if "flutter-action" in s.get("uses", ""))
        self.assertIs(False, flutter["with"]["cache"])
        self.assertEqual("${{ env.FLUTTER_VERSION }}", flutter["with"]["flutter-version"])
        self.assertNotIn("actions/cache", self.text)

    def test_cli_tools_come_from_the_hash_lock(self):
        self.assertIn(LOCKED_INSTALL, self.step("build", "Toolchain")["run"])
        self.assertNotRegex(self.text, r"pip3? install [^\n]*codemagic-cli-tools")

    def test_cli_tools_never_caches_its_token_on_disk(self):
        self.assertEqual("1", str(self.doc["env"]["APP_STORE_CONNECT_DISABLE_JWT_CACHE"]))

    def test_secrets_only_reach_step_env_in_the_main_only_environment(self):
        self.assertNotRegex(yaml.safe_dump(self.doc.get("env", {})), SECRET_REF)
        for name, job in self.jobs.items():
            outside_steps = {k: v for k, v in job.items() if k != "steps"}
            self.assertNotRegex(yaml.safe_dump(outside_steps), SECRET_REF, name)
            if SECRET_REF.search(yaml.safe_dump(job)):
                self.assertEqual("testflight", job.get("environment"), name)
            for step in job.get("steps", []):
                label = f"{name}: {step.get('name', step.get('uses'))}"
                outside_env = {k: v for k, v in step.items() if k != "env"}
                self.assertNotRegex(yaml.safe_dump(outside_env), SECRET_REF, label)
                for value in step.get("env", {}).values():
                    if SECRET_REF.search(str(value)):
                        self.assertRegex(str(value), r"^\$\{\{ secrets\.[A-Z0-9_]+ \}\}$", label)

    def test_secrets_never_reach_github_env_or_outputs(self):
        secret_vars = {k for _, s in self.steps() for k, v in s.get("env", {}).items()
                       if SECRET_REF.search(str(v))}
        for job, step in self.steps():
            for line in step.get("run", "").splitlines():
                if re.search(r"GITHUB_(ENV|OUTPUT|PATH|STEP_SUMMARY)", line):
                    for var in secret_vars:
                        self.assertNotRegex(line, rf"\b{var}\b", f"{job}: {step.get('name')}")

    def test_builds_only_main(self):
        self.assertEqual("github.ref == 'refs/heads/main'", self.jobs["build"]["if"])
        self.assertEqual(["build"], list(self.jobs))

    def test_first_step_pins_the_checked_commit(self):
        first = self.jobs["build"]["steps"][0]
        self.assertEqual("${{ inputs.sha }}", first["env"]["WANT"])
        self.assertIn('"$WANT" != "$GITHUB_SHA"', first["run"])

    def test_inputs_never_reach_a_shell_unquoted(self):
        for job, step in self.steps():
            self.assertNotIn("${{", step.get("run", ""), f"{job}: {step.get('name')}")

    def test_checkout_never_keeps_the_token(self):
        checkouts = [s for _, s in self.steps() if "actions/checkout" in s.get("uses", "")]
        self.assertTrue(checkouts)
        for step in checkouts:
            self.assertIs(False, step.get("with", {}).get("persist-credentials"))

    def test_only_the_manifest_is_uploaded(self):
        uploads = [s for _, s in self.steps() if "upload-artifact" in s.get("uses", "")]
        self.assertEqual(1, len(uploads))
        self.assertEqual("${{ runner.temp }}/testflight-build.json", uploads[0]["with"]["path"])
        self.assertIs(True, uploads[0]["with"]["overwrite"])

    def test_no_shell_tracing_or_verbose_flutter(self):
        for job, step in self.steps():
            label = f"{job}: {step.get('name')}"
            # Continuation lines joined, so a flag on the next line still counts.
            run = live(step.get("run", ""))
            self.assertNotRegex(run, TRACING, label)
            self.assertNotRegex(str(step.get("shell", "")), TRACING + r"|-\w*x\b", label)
            # --wrap splits long lines, and a mask only matches within one line.
            self.assertNotRegex(run, r"\bflutter\b[^\n]*(\s-v\b|--verbose|--wrap)", label)
            self.assertNotRegex(run, r"Generated\.xcconfig|flutter_export_environment", label)
            self.assertNotRegex(run, r"(?m)(^|[;&|(]\s*)(env|printenv|set|export -p|declare -x)\s*($|[|>;&)])",
                                label)
        for scope in (self.doc, *self.jobs.values()):
            shell = str(scope.get("defaults", {}).get("run", {}).get("shell", ""))
            self.assertNotRegex(shell, TRACING + r"|-\w*x\b")

    def test_nothing_can_wave_a_failed_check_through(self):
        for name, job in self.jobs.items():
            self.assertNotIn("continue-on-error", job, name)
            self.assertNotRegex(str(job.get("if", "")), UNCONDITIONAL, name)
            for step in job.get("steps", []):
                self.assertNotIn("continue-on-error", step, f"{name}: {step.get('name')}")
        self.assertNotIn("if", self.step("build", "Check the IPA"))

    def test_signing_never_changes_the_account(self):
        # --create only behind the create_signing input, which defaults to off.
        step = self.step("build", "Create signing files")
        signing = live(step["run"])
        self.assertIn("fetch-signing-files", signing)
        self.assertEqual("${{ inputs.create_signing }}", step["env"]["CREATE"])
        self.assertEqual(1, signing.count("--create"))
        self.assertIn('if [ "$CREATE" = true ]; then create="--create"; fi', signing)
        create = self.doc[True]["workflow_dispatch"]["inputs"]["create_signing"]
        self.assertIs(False, create["default"])

    def test_signing_leaves_nothing_readable_behind(self):
        sign = live(self.step("build", "Create signing files")["run"])
        self.assertIn("umask 077", sign)
        self.assertIn("trap 'rm -f \"$key\"' EXIT", sign)
        self.assertRegex(sign, r"keychain initialize --password @env:\w+")
        self.assertNotIn('-k ""', sign)
        for folder in ("Library/Developer/Xcode/UserData/Certificates", "Library/MobileDevice/Certificates"):
            self.assertIn(f'"$HOME/{folder}/"*.p12', sign)
        self.assertIn('echo "::add-mask::$line"', sign)

    def test_xcode_is_the_exact_build(self):
        self.assertIn('grep -q "Build version $XCODE_BUILD"', self.step("build", "Toolchain")["run"])

    def test_build_flags(self):
        self.assertIn('--build-number="$BUILD_NUMBER"', self.text)
        self.assertIn('--export-options-plist="$RUNNER_TEMP/export_options.plist"', self.text)
        self.assertNotIn("dart-define", self.text)

    def test_build_numbers_keep_rising(self):
        # Installed apps compare build numbers only; the Swift app shipped up to 8, and
        # Flutter builds start at 100.
        self.assertGreaterEqual(int(self.doc["env"]["BUILD_NUMBER_FLOOR"]), 99)
        step = self.step("build", "Pick the build number")
        self.assertIn('get-latest-testflight-build-number "$ASC_APP_ID" --all-versions', step["run"])
        self.assertIn("''|*[!0-9]*)", step["run"])
        self.assertIn('echo "BUILD_NUMBER=$next" >> "$GITHUB_ENV"', step["run"])

    def test_processing_waits_for_the_right_build(self):
        names = [s.get("name") for _, s in self.steps("build")]
        self.assertLess(names.index("Upload to TestFlight"), names.index("Wait for Apple to finish processing"))
        wait = self.step("build", "Wait for Apple to finish processing")
        self.assertEqual("inputs.upload", wait["if"])
        self.assertIn('--build-version-number "$BUILD_NUMBER"', wait["run"])
        self.assertIn("|| state=", wait["run"])
        # An hour of processing has to fit in the job.
        self.assertGreaterEqual(self.jobs["build"]["timeout-minutes"], 75)

    def test_background_prep_runs_before_any_secret_and_must_succeed(self):
        names = [s.get("name") for _, s in self.steps("build")]
        toolchain = self.step("build", "Toolchain")
        self.assertNotIn("env", toolchain)
        self.assertLess(names.index("Toolchain"), names.index("Create signing files"))
        self.assertIn('wait "$prep"', toolchain["run"])

    def test_flutter_and_xcode_are_pinned(self):
        self.assertRegex(str(self.doc["env"]["FLUTTER_VERSION"]), r"^\d+\.\d+\.\d+$")
        fvmrc = (ROOT / ".fvmrc").read_text(encoding="utf-8")
        self.assertIn(f'"{self.doc["env"]["FLUTTER_VERSION"]}"', fvmrc)
        pubspec = yaml.safe_load((ROOT / "pubspec.yaml").read_text(encoding="utf-8"))
        self.assertEqual(str(self.doc["env"]["FLUTTER_VERSION"]), str(pubspec["environment"]["flutter"]))
        compile_env = yaml.safe_load((WORKFLOW.parent / "app-compile.yml").read_text(encoding="utf-8"))["env"]
        for key in ("FLUTTER_VERSION", "XCODE_VERSION", "XCODE_BUILD"):
            self.assertEqual(str(self.doc["env"][key]), str(compile_env[key]), key)

    def test_ipa_is_checked_before_it_is_uploaded(self):
        names = [s.get("name") for _, s in self.steps("build")]
        self.assertLess(names.index("Check the IPA"), names.index("Upload to TestFlight"))
        self.assertEqual("inputs.upload", self.step("build", "Upload to TestFlight")["if"])


class OtherWorkflowsTest(unittest.TestCase):
    def test_only_this_workflow_can_sign_or_upload(self):
        # Environment secrets reach any job on main that names the environment,
        # whatever its trigger.
        for path in sorted(WORKFLOW.parent.glob("*.y*ml")):
            if path.name == WORKFLOW.name:
                continue
            doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
            text = yaml.safe_dump(doc)
            for name, job in (doc.get("jobs") or {}).items():
                self.assertNotIn("environment", job, f"{path.name}: {name}")
            self.assertNotRegex(text, SECRET_REF, path.name)
            self.assertNotRegex(text, r"app-store-connect|altool", path.name)


if __name__ == "__main__":
    unittest.main()
