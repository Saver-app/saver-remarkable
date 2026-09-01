use std::time::Duration;

use anyhow::{bail, Context, Result};
use serde::Deserialize;

pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
pub const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

const RETRY_BACKOFF: [Duration; 2] = [Duration::from_millis(1500), Duration::from_secs(4)];

const DROPPED_MESSAGE: &str = "Saver's servers had a hiccup. Please try again in a moment.";

const MAX_DETAIL_CHARS: usize = 200;

#[derive(Deserialize)]
struct ErrorResponse {
    error: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Retry {
    OnColdStart,
    Never,
}

#[derive(Debug, PartialEq, Eq)]
enum Failure {
    Reported(String),
    Dropped(String),
}

pub fn blocking_client() -> reqwest::blocking::Client {
    reqwest::blocking::Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .timeout(REQUEST_TIMEOUT)
        .build()
        .expect("building the Saver HTTP client")
}

fn network_error_message(err: &reqwest::Error) -> String {
    if err.is_timeout() {
        "Saver took too long to respond. Check your Wi-Fi and try again.".to_string()
    } else if err.is_connect() {
        "Could not reach Saver. Check your Wi-Fi and try again.".to_string()
    } else {
        format!("Could not reach Saver: {err}")
    }
}

fn summarize(text: &str) -> String {
    let flattened = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if flattened.chars().count() <= MAX_DETAIL_CHARS {
        return flattened;
    }
    let head: String = flattened.chars().take(MAX_DETAIL_CHARS).collect();
    format!("{head}…")
}

fn classify(text: &str) -> Failure {
    match serde_json::from_str::<ErrorResponse>(text) {
        Ok(parsed) => Failure::Reported(parsed.error),
        Err(_) => Failure::Dropped(summarize(text)),
    }
}

pub fn send_json(
    label: &str,
    retry: Retry,
    build: impl Fn() -> reqwest::blocking::RequestBuilder,
) -> Result<serde_json::Value> {
    let mut attempt = 0usize;
    loop {
        let response = build()
            .send()
            .map_err(|err| anyhow::anyhow!(network_error_message(&err)))?;

        let status = response.status();
        let text = response.text().context("reading response body")?;

        if status.is_success() {
            return serde_json::from_str(&text).context("parsing response body");
        }

        let detail = match classify(&text) {
            Failure::Reported(message) => bail!("{label} ({status}): {message}"),
            Failure::Dropped(detail) => detail,
        };

        eprintln!("saver-remarkable: {label} - dropped before reaching Saver ({status}): {detail}");

        let retryable = status.is_server_error() && retry == Retry::OnColdStart;
        match RETRY_BACKOFF.get(attempt).filter(|_| retryable) {
            Some(wait) => {
                std::thread::sleep(*wait);
                attempt += 1;
            }
            None => bail!("{DROPPED_MESSAGE}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn savers_own_error_is_passed_through() {
        assert_eq!(
            classify(r#"{"error":"Internal error."}"#),
            Failure::Reported("Internal error.".to_string())
        );
    }

    #[test]
    fn the_edges_plain_text_is_a_dropped_request() {
        assert_eq!(
            classify("Internal Error"),
            Failure::Dropped("Internal Error".to_string())
        );
    }

    #[test]
    fn an_html_error_page_is_a_dropped_request() {
        assert_eq!(
            classify("<html>\n  <title>500</title>\n</html>"),
            Failure::Dropped("<html> <title>500</title> </html>".to_string())
        );
    }

    #[test]
    fn a_long_body_is_capped() {
        let summary = summarize(&"x".repeat(MAX_DETAIL_CHARS * 2));
        assert_eq!(summary.chars().count(), MAX_DETAIL_CHARS + 1);
        assert!(summary.ends_with('…'));
    }
}
