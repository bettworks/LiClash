// URL 启动器：使用系统默认浏览器打开 URL

// 打开 URL
pub fn open_url(url: &str) -> Result<(), String> {
    log::info!("尝试在浏览器中打开 URL：{}", url);

    webbrowser::open(url).map_err(|e| {
        let error_msg = format!("打开 URL 失败：{}", e);
        log::error!("{}", error_msg);
        error_msg
    })?;

    log::info!("成功打开 URL");
    Ok(())
}
