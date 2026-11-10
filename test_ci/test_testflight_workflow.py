"""Static checks on .github/workflows/testflight.yml (ported from Kazumi's test/ci). The
repo is public, so the workflow's logs and artifacts are too; these keep the signing
secrets out of both, and keep a dry run from ever uploading."""

import json
import plistlib
import re
import shutil
import subprocess
import tempfile
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


def source_program(run: str) -> str:
    """The jq program the release job's heredoc writes."""
    return re.search(r"<<'JQ'\n(.*?)\nJQ\n", run, re.S).group(1)


def unlisted_program(run: str) -> str:
    """The jq program the sideload job names the usage descriptions source.json would miss with."""
    return re.search(r"unlisted=\$\(jq -r '(.*?)' \"\$RUNNER_TEMP/info.json\"\)", run, re.S).group(1)


def require_jq():
    # The workflow's jq programs run on GitHub only for a real release, so these tests are their one check before it.
    if not shutil.which("jq"):
        raise AssertionError("jq is not on PATH: the workflow's jq programs are checked only here before a real "
                             "release, so install jq rather than skip them")


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
        # Only the release job may write, to publish the unsigned IPA.
        self.assertEqual({"contents": "read"}, self.doc["permissions"])
        for name, job in self.jobs.items():
            if name == "release":
                self.assertEqual({"contents": "write"}, job["permissions"])
            else:
                self.assertNotIn("permissions", job, name)

    def test_actions_are_pinned_to_commits(self):
        for job, step in self.steps():
            if "uses" in step:
                self.assertRegex(step["uses"], PINNED, f"{job}: {step['uses']}")

    def test_no_shared_caches(self):
        # Enforced by the cache service for every step, not just flutter-action's.
        self.assertEqual("none", self.doc.get("cache-mode"))
        flutters = [s for _, s in self.steps() if "flutter-action" in s.get("uses", "")]
        self.assertEqual(2, len(flutters))
        for flutter in flutters:
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
        self.assertEqual(["build", "sideload", "release"], list(self.jobs))
        # Both wait on the build, so they skip whenever it does.
        self.assertEqual("build", self.jobs["sideload"]["needs"])
        self.assertEqual(["build", "sideload"], self.jobs["release"]["needs"])

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

    def test_only_the_manifest_and_the_unsigned_ipa_are_uploaded(self):
        uploads = {job: s for job, s in self.steps() if "upload-artifact" in s.get("uses", "")}
        self.assertEqual({"build", "sideload"}, set(uploads))
        self.assertEqual("${{ runner.temp }}/testflight-build.json", uploads["build"]["with"]["path"])
        self.assertEqual(["${{ runner.temp }}/BiliFast-*.ipa", "${{ runner.temp }}/sideload-app.json",
                          "${{ runner.temp }}/release-notes.md"],
                         uploads["sideload"]["with"]["path"].splitlines())
        for upload in uploads.values():
            self.assertIs(True, upload["with"]["overwrite"])

    def test_the_unsigned_ipa_never_meets_a_secret(self):
        # The signed IPA's profile and certificate carry KaiC's legal name; the public one is built apart.
        for name in ("sideload", "release"):
            job = self.jobs[name]
            self.assertNotIn("environment", job, name)
            self.assertNotRegex(yaml.safe_dump(job), SECRET_REF, name)
            self.assertNotRegex(yaml.safe_dump(job), r"app-store-connect|keychain|export_options", name)
        self.assertNotIn("github.token", yaml.safe_dump(self.jobs["sideload"]))
        build = live(self.step("sideload", "Build the unsigned IPA")["run"])
        self.assertIn("flutter build ios --release --no-codesign", build)
        self.assertIn("embedded.mobileprovision", build)
        self.assertNotIn("checkout", yaml.safe_dump(self.jobs["release"]))

    def test_the_release_job_runs_nothing_from_the_repo(self):
        # It holds the write token; a repo script there would be code the token runs, so it is shell and jq inline.
        uses = [s["uses"] for _, s in self.steps("release") if "uses" in s]
        self.assertEqual(1, len(uses))
        self.assertIn("actions/download-artifact@", uses[0])
        for _, step in self.steps("release"):
            run = step.get("run", "")
            if "<<'JQ'" in run:
                run = run.replace(source_program(run), "")
            self.assertNotRegex(live(run),r"\b(python3?|node|ruby|perl|bash|sh|uv|fvm|flutter|dart|make|npm|npx)\b"
                                     r"|\bsource\s|(^|\s)\.\s|\./|scripts/|tools/", step.get("name"))
        source = self.step("release", "Write the source")["run"]
        # jq reads only the program this step writes and the artifact's description, never a file from the repo.
        self.assertIn("cat > \"$RUNNER_TEMP/source.jq\" <<'JQ'", source)
        jq = re.findall(r"(?m)^\s*jq\b.*$", live(source.replace(source_program(source), "")))
        self.assertEqual(1, len(jq))
        self.assertEqual(['"$RUNNER_TEMP/source.jq"'], re.findall(r"\s-f (\S+)", jq[0]))

    def test_the_write_token_reaches_only_the_publish_step(self):
        for _, step in self.steps("release"):
            has_token = "github.token" in yaml.safe_dump(step)
            self.assertEqual(step.get("name") == "Publish", has_token, step.get("name", step.get("uses")))

    def test_every_release_carries_the_source(self):
        names = [s.get("name") for _, s in self.steps("release")]
        self.assertLess(names.index("Write the source"), names.index("Publish"))
        self.assertIn('> "$RUNNER_TEMP/source.json"', self.step("release", "Write the source")["run"])
        publish = live(self.step("release", "Publish")["run"])
        self.assertIn('gh release create "v$BUILD_NAME-$BUILD_NUMBER" "$1" "$RUNNER_TEMP/source.json"', publish)
        self.assertIn("/releases/latest/download/source.json", publish)
        # The app adds and checks the source by this address, so the asset's name is the contract.
        links = (ROOT / "lib/sideload/sideload_links.dart").read_text(encoding="utf-8")
        url = re.search(r"const sourceUrl = '([^']+)'", links).group(1)
        self.assertEqual("https://github.com/KaiC5504/BiliFast/releases/latest/download/source.json", url)

    def test_the_source_program_gets_every_argument_it_uses(self):
        # A missing --arg is a jq compile error, which would only show on an upload's release job.
        source = self.step("release", "Write the source")["run"]
        program = source_program(source)
        used = set(re.findall(r"\$(\w+)", program)) - {"why", "__loc__"}
        passed = set(re.findall(r"--(?:arg|argjson|rawfile) (\w+) ", source))
        self.assertEqual(used, passed)
        self.assertIn('--argjson size "$size"', source)
        self.assertIn('--arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)"', source)
        self.assertIn('-f "$RUNNER_TEMP/source.jq" ipa/sideload-app.json > "$RUNNER_TEMP/source.json"', live(source))

    def test_the_sideload_job_describes_the_app_it_built(self):
        names = [s.get("name") for _, s in self.steps("sideload")]
        self.assertLess(names.index("Build the unsigned IPA"), names.index("Describe the unsigned app"))
        describe = live(self.step("sideload", "Describe the unsigned app")["run"])
        self.assertIn("build/ios/iphoneos/Runner.app/Info.plist", describe)
        self.assertIn('"^NS[A-Za-z]+UsageDescription$"', describe)
        self.assertIn("minOSVersion: .MinimumOSVersion", describe)
        self.assertIn("jq -e", describe)

    def test_a_usage_description_source_json_would_miss_fails_the_build(self):
        # AltStore and SideStore count every key containing UsageDescription; the three filters have to agree.
        describe = self.step("sideload", "Describe the unsigned app")["run"]
        unlisted = unlisted_program(describe)
        privacy_filter = 'test("^NS[A-Za-z]+UsageDescription$")'
        self.assertIn('contains("UsageDescription")', unlisted)
        self.assertIn(privacy_filter, unlisted)
        self.assertIn(f"privacy: with_entries(select(.key | {privacy_filter}))", describe)
        self.assertIn(privacy_filter, source_program(self.step("release", "Write the source")["run"]))
        code = live(describe)
        self.assertRegex(code, r'\nif \[ -n "\$unlisted" \]; then\n\s*echo [^\n]*\n\s*exit 1\n\s*fi\n')
        self.assertLess(code.index("unlisted=$(jq"), code.index('> "$RUNNER_TEMP/sideload-app.json"'))

    def test_releases_only_follow_an_upload(self):
        self.assertEqual("inputs.upload", self.jobs["release"]["if"])
        self.assertNotIn("if", self.jobs["sideload"])
        publish = live(self.step("release", "Publish")["run"])
        self.assertIn('gh release create "v$BUILD_NAME-$BUILD_NUMBER"', publish)
        self.assertIn('--target "$GITHUB_SHA"', publish)
        self.assertEqual("${{ github.token }}", self.step("release", "Publish")["env"]["GH_TOKEN"])

    def test_every_release_says_what_changed(self):
        # The release job checks nothing out, so the notes ride the sideload job's artifact.
        take = live(self.step("sideload", "Take the release notes")["run"])
        self.assertIn("docs/release-notes.md", take)
        self.assertIn("exit 1", take)
        self.assertIn('cp docs/release-notes.md "$RUNNER_TEMP/release-notes.md"', take)
        self.assertTrue((ROOT / "docs/release-notes.md").read_text(encoding="utf-8").strip())
        publish = live(self.step("release", "Publish")["run"])
        self.assertLess(publish.index("cat ipa/release-notes.md"), publish.index("未签名的 IPA"))
        source = self.step("release", "Write the source")["run"]
        self.assertIn("--rawfile notes ipa/release-notes.md", source)
        self.assertIn('localizedDescription: "\\($notes', source_program(source))

    def test_release_note_addresses_end_before_the_chinese(self):
        # GitHub's autolinker runs a bare address on into the full-width comma after it, and a tap on the link 404s.
        publish = self.step("release", "Publish")["run"]
        notes = re.search(r"<<EOF\n(.*?)\nEOF\n", publish, re.S).group(1)
        addresses = re.findall(r"(?:\$GITHUB_SERVER_URL|https?://)[^\s\\`]*", notes)
        self.assertTrue(addresses)
        for address in addresses:
            self.assertTrue(address.isascii(), address)

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

    def test_build_numbers_count_within_the_version(self):
        # 1.0.0 starts again at 1: build numbers only have to be unique within a version.
        self.assertNotIn("BUILD_NUMBER_FLOOR", self.text)
        self.assertNotIn("--all-versions", self.text)
        step = self.step("build", "Pick the build number")
        self.assertIn('get-latest-testflight-build-number "$ASC_APP_ID" --pre-release-version "$BUILD_NAME"', step["run"])
        self.assertIn("next=$(( 10#$latest + 1 ))", step["run"])
        self.assertIn("''|*[!0-9]*)", step["run"])
        self.assertIn('echo "BUILD_NUMBER=$next" >> "$GITHUB_ENV"', step["run"])

    def test_processing_waits_for_the_right_build(self):
        names = [s.get("name") for _, s in self.steps("build")]
        self.assertLess(names.index("Upload to TestFlight"), names.index("Wait for Apple to finish processing"))
        wait = self.step("build", "Wait for Apple to finish processing")
        self.assertEqual("inputs.upload", wait["if"])
        # Build 1 also exists in 0.1.0, so the wait matches the version too, or it would find that old build.
        self.assertIn('--pre-release-version "$BUILD_NAME" --build-version-number "$BUILD_NUMBER"', wait["run"])
        # A failed check is retried a few times, then fails the step with its error, never loops for the hour.
        self.assertIn('state="no answer', wait["run"])
        self.assertIn('if [ "$misses" -ge 8 ]', wait["run"])
        # macOS runners have no GNU timeout (build 100's wait failed every call on it).
        self.assertNotRegex(wait["run"], r"(^|[\s(])timeout ")
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

    def test_version_matches_the_pubspec(self):
        pubspec = yaml.safe_load((ROOT / "pubspec.yaml").read_text(encoding="utf-8"))
        self.assertEqual(str(self.doc["env"]["BUILD_NAME"]), str(pubspec["version"]).split("+")[0])

    def test_ipa_is_checked_before_it_is_uploaded(self):
        names = [s.get("name") for _, s in self.steps("build")]
        self.assertLess(names.index("Check the IPA"), names.index("Upload to TestFlight"))
        self.assertEqual("inputs.upload", self.step("build", "Upload to TestFlight")["if"])


class SourceProgramTest(unittest.TestCase):
    """Runs the release job's jq program on a sample description: the release job only runs on an upload, so this is
    the program's only check before a real release."""

    APP = {
        "bundleIdentifier": "com.kaichuan.bilifast",
        "version": "1.3.0",
        "buildVersion": "8",
        "minOSVersion": "26.0",
        "privacy": {
            "NSCameraUsageDescription": "用于拍照添加到评论。",
            "NSPhotoLibraryUsageDescription": "用于在评论里添加图片。",
        },
    }
    IPA = "https://github.com/KaiC5504/BiliFast/releases/download/v1.3.0-8/BiliFast-1.3.0-8.ipa"

    @classmethod
    def setUpClass(cls):
        require_jq()
        doc = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
        step = next(s for s in doc["jobs"]["release"]["steps"] if s.get("name") == "Write the source")
        cls.program = source_program(step["run"])

    def run_program(self, app, size=48213504, build="8"):
        with tempfile.TemporaryDirectory() as folder:
            program = Path(folder, "source.jq")
            program.write_text(self.program, encoding="utf-8", newline="\n")
            described = Path(folder, "sideload-app.json")
            described.write_text(json.dumps(app, ensure_ascii=False), encoding="utf-8")
            args = {"bundle": "com.kaichuan.bilifast", "version": "1.3.0", "build": build,
                    "date": "2026-11-04T08:00:00Z", "url": self.IPA,
                    "icon": "https://raw.githubusercontent.com/KaiC5504/BiliFast/main/ios/Runner/Assets.xcassets/"
                            "AppIcon.appiconset/icon-1024.png",
                    "website": "https://github.com/KaiC5504/BiliFast"}
            notes = Path(folder, "release-notes.md")
            notes.write_text("- 第一条\n- 第二条\n\n", encoding="utf-8", newline="\n")
            command = ["jq"]
            for name, value in args.items():
                command += ["--arg", name, value]
            command += ["--rawfile", "notes", str(notes)]
            command += ["--argjson", "size", str(size), "-f", str(program), str(described)]
            return subprocess.run(command, capture_output=True)

    def source(self, app):
        result = self.run_program(app)
        self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", "replace"))
        return json.loads(result.stdout.decode("utf-8"))

    def test_the_source_has_altstores_fields(self):
        # faq.altstore.io/developers/make-a-source, and the decoders of AltStore, SideStore and Feather.
        source = self.source(self.APP)
        self.assertEqual("BiliFast", source["name"])
        self.assertEqual("com.kaichuan.bilifast.source", source["identifier"])
        self.assertEqual("#FB7299", source["tintColor"])
        self.assertEqual([], source["news"])
        for key in ("subtitle", "iconURL", "website"):
            self.assertIsInstance(source[key], str, key)
        [app] = source["apps"]
        self.assertEqual(("BiliFast", "com.kaichuan.bilifast", "KaiC", "entertainment"),
                         (app["name"], app["bundleIdentifier"], app["developerName"], app["category"]))
        for key in ("subtitle", "localizedDescription", "iconURL", "tintColor"):
            self.assertIsInstance(app[key], str, key)
        self.assertTrue(app["iconURL"].endswith("/main/ios/Runner/Assets.xcassets/AppIcon.appiconset/icon-1024.png"))
        self.assertTrue((ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/icon-1024.png").is_file())
        [version] = app["versions"]
        self.assertEqual({"version": "1.3.0", "buildVersion": "8", "date": "2026-11-04T08:00:00Z",
                          "downloadURL": self.IPA, "size": 48213504, "minOSVersion": "26.0"},
                         {k: v for k, v in version.items() if k != "localizedDescription"})
        self.assertEqual("- 第一条\n- 第二条\n\n发布页：https://github.com/KaiC5504/BiliFast/releases/tag/v1.3.0-8",
                         version["localizedDescription"])
        self.assertEqual({"entitlements": [], "privacy": self.APP["privacy"]}, app["appPermissions"])

    def test_a_wrong_description_publishes_nothing(self):
        wrong = [
            {**self.APP, "bundleIdentifier": "com.example.other"},
            {**self.APP, "buildVersion": "7"},
            {**self.APP, "version": "1.2.0"},
            {k: v for k, v in self.APP.items() if k != "minOSVersion"},
            {**self.APP, "minOSVersion": "latest"},
            {**self.APP, "privacy": [{"name": "Camera", "usageDescription": "x"}]},
            {**self.APP, "privacy": {"NSCameraUsageDescription": ""}},
            {**self.APP, "privacy": {"CFBundleIdentifier": "com.kaichuan.bilifast"}},
        ]
        for app in wrong:
            result = self.run_program(app)
            self.assertNotEqual(0, result.returncode, app)
            self.assertIn(b"source.json:", result.stderr, app)
            self.assertEqual(b"", result.stdout, app)
        self.assertNotEqual(0, self.run_program(self.APP, size=0).returncode)


class UsageDescriptionCheckTest(unittest.TestCase):
    """Runs the sideload job's check that source.json can list every usage description, on the app's Info.plist."""

    @classmethod
    def setUpClass(cls):
        require_jq()
        doc = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
        step = next(s for s in doc["jobs"]["sideload"]["steps"] if s.get("name") == "Describe the unsigned app")
        cls.program = unlisted_program(step["run"])
        with (ROOT / "ios/Runner/Info.plist").open("rb") as plist:
            cls.info = plistlib.load(plist)

    def unlisted(self, info):
        with tempfile.TemporaryDirectory() as folder:
            program = Path(folder, "unlisted.jq")
            program.write_text(self.program, encoding="utf-8", newline="\n")
            converted = Path(folder, "info.json")
            converted.write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
            result = subprocess.run(["jq", "-r", "-f", str(program), str(converted)], capture_output=True)
        self.assertEqual(0, result.returncode, result.stderr.decode("utf-8", "replace"))
        return result.stdout.decode("utf-8").splitlines()

    def test_the_apps_usage_descriptions_all_reach_the_source(self):
        self.assertTrue(any("UsageDescription" in key for key in self.info))
        self.assertEqual([], self.unlisted(self.info))

    def test_a_key_the_privacy_filter_misses_is_named(self):
        for key in ("NFCReaderUsageDescription", "NSCameraUsageDescription~ipad", "NSUser_TrackingUsageDescription"):
            self.assertEqual([key], self.unlisted({**self.info, key: "用于测试。"}), key)

    def test_an_empty_or_non_string_description_is_named(self):
        for value in ("", 1, True, None, ["用于测试。"], {"text": "用于测试。"}):
            info = {**self.info, "NSCameraUsageDescription": value}
            self.assertEqual(["NSCameraUsageDescription"], self.unlisted(info), value)


class OtherWorkflowsTest(unittest.TestCase):
    def test_testflight_is_the_only_workflow(self):
        # KaiC's call (2026-10-18): keep only the workflows that matter; tests run locally in scripts/gate.py.
        names = sorted(p.name for p in WORKFLOW.parent.glob("*.y*ml"))
        self.assertEqual([WORKFLOW.name], names, "a new workflow needs KaiC's OK first")

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
