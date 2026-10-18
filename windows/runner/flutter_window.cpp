#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "bilifast/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setClientSize") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        const auto width = args ? args->find(flutter::EncodableValue("width")) : flutter::EncodableMap::const_iterator();
        const auto height = args ? args->find(flutter::EncodableValue("height")) : flutter::EncodableMap::const_iterator();
        if (!args || width == args->end() || height == args->end() ||
            !std::holds_alternative<double>(width->second) || !std::holds_alternative<double>(height->second)) {
          result->Error("bad-args", "width and height expected");
          return;
        }
        SetClientSize(std::get<double>(width->second), std::get<double>(height->second));
        result->Success();
      });
  // The iPhone 17 Pro Max's screen in points, upright.
  SetClientSize(440, 956);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetClientSize(double width, double height) {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  const UINT dpi = GetDpiForWindow(hwnd);
  const double scale = dpi / 96.0;
  RECT frame = {0, 0, static_cast<LONG>(width * scale), static_cast<LONG>(height * scale)};
  AdjustWindowRectExForDpi(&frame, static_cast<DWORD>(GetWindowLong(hwnd, GWL_STYLE)), FALSE,
                           static_cast<DWORD>(GetWindowLong(hwnd, GWL_EXSTYLE)), dpi);
  const LONG w = frame.right - frame.left;
  const LONG h = frame.bottom - frame.top;
  RECT current;
  GetWindowRect(hwnd, &current);
  MONITORINFO info{sizeof(info)};
  GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &info);
  const RECT& work = info.rcWork;
  LONG x = current.left;
  LONG y = current.top;
  if (x + w > work.right) x = std::max(work.left, work.right - w);
  if (y + h > work.bottom) y = std::max(work.top, work.bottom - h);
  SetWindowPos(hwnd, nullptr, x, y, w, h, SWP_NOZORDER | SWP_NOACTIVATE);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
