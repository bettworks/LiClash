// 覆写处理消息协议
//
// 目的：定义 Dart 与 Rust 之间覆写处理的通信接口

use super::processor::OverrideProcessor;
use crate::clash::subscription::ProxyParser;
use rinf::{DartSignal, RustSignal, SignalPiece};
use serde::{Deserialize, Serialize};

// 覆写格式枚举
#[derive(Deserialize, Serialize, SignalPiece, Clone, Copy, Debug)]
pub enum OverrideFormat {
    Yaml = 0,
    Javascript = 1,
}

// 单个覆写配置
#[derive(Debug, Deserialize, Serialize, SignalPiece, Clone)]
pub struct OverrideConfig {
    pub id: String,
    pub name: String,
    pub format: OverrideFormat,
    pub content: String,
}

// Dart → Rust：应用覆写请求
#[derive(Deserialize, DartSignal)]
pub struct ApplyOverridesRequest {
    pub base_config_content: String,
    pub overrides: Vec<OverrideConfig>,
}

// Rust → Dart：应用覆写响应
#[derive(Serialize, RustSignal)]
pub struct ApplyOverridesResponse {
    pub success: bool,
    pub result_config: String,
    pub error_message: String,
    pub logs: Vec<String>,
}

impl ApplyOverridesRequest {
    // 处理覆写应用请求
    //
    // 目的：接收 Dart 发送的配置和覆写列表，处理后返回结果
    pub fn handle(self) {
        log::info!("收到应用覆写请求，覆写数量：{}", self.overrides.len());

        let mut processor = match OverrideProcessor::new() {
            Ok(p) => p,
            Err(e) => {
                log::error!("初始化覆写处理器失败：{}", e);
                let response = ApplyOverridesResponse {
                    success: false,
                    result_config: String::new(),
                    error_message: format!("初始化处理器失败：{}", e),
                    logs: vec![],
                };
                response.send_signal_to_dart();
                return;
            }
        };

        // 先解析订阅内容为标准 Clash 配置
        let parsed_config = match ProxyParser::parse_subscription(&self.base_config_content) {
            Ok(config) => config,
            Err(e) => {
                log::error!("订阅解析失败：{}", e);
                let response = ApplyOverridesResponse {
                    success: false,
                    result_config: String::new(),
                    error_message: format!("订阅解析失败：{}", e),
                    logs: vec![],
                };
                response.send_signal_to_dart();
                return;
            }
        };

        log::info!("订阅解析成功，配置长度：{}字节", parsed_config.len());

        match processor.apply_overrides(&parsed_config, self.overrides) {
            Ok(result) => {
                log::info!("覆写处理成功");
                let response = ApplyOverridesResponse {
                    success: true,
                    result_config: result,
                    error_message: String::new(),
                    logs: vec!["处理成功".to_string()],
                };
                response.send_signal_to_dart();
            }
            Err(e) => {
                log::error!("覆写处理失败：{}", e);
                let response = ApplyOverridesResponse {
                    success: false,
                    result_config: String::new(),
                    error_message: e,
                    logs: vec![],
                };
                response.send_signal_to_dart();
            }
        }
    }
}

// Dart → Rust：解析订阅请求
#[derive(Deserialize, DartSignal)]
pub struct ParseSubscriptionRequest {
    pub content: String,
}

// Rust → Dart：解析订阅响应
#[derive(Serialize, RustSignal)]
pub struct ParseSubscriptionResponse {
    pub success: bool,
    pub parsed_config: String,
    pub error_message: String,
}

impl ParseSubscriptionRequest {
    // 处理订阅解析请求
    //
    // 目的：接收原始订阅内容（标准 YAML、Base64 编码或纯文本代理链接），解析为标准 Clash 配置
    pub fn handle(self) {
        log::info!("收到订阅解析请求，内容长度：{}字节", self.content.len());

        match ProxyParser::parse_subscription(&self.content) {
            Ok(parsed_config) => {
                log::info!("订阅解析成功，配置长度：{}字节", parsed_config.len());
                let response = ParseSubscriptionResponse {
                    success: true,
                    parsed_config,
                    error_message: String::new(),
                };
                response.send_signal_to_dart();
            }
            Err(e) => {
                log::error!("订阅解析失败：{}", e);
                let response = ParseSubscriptionResponse {
                    success: false,
                    parsed_config: String::new(),
                    error_message: e,
                };
                response.send_signal_to_dart();
            }
        }
    }
}
