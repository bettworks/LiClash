// UTF-8 BOM
#include "flutter_window.h"

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

  // 创建 Flutter 视图控制器
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left,
      frame.bottom - frame.top,
      project_);
  
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  
  // 注册 Flutter 插件
  RegisterPlugins(flutter_controller_->engine());
  
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 让 Flutter 优先处理消息
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
      // 字体设置改变时重新加载系统字体
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}