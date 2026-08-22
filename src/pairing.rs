use std::time::Duration;

use anyhow::{bail, Context, Result};
use qrcode::{Color, QrCode};
use serde::Deserialize;
use serde_json::json;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);

pub struct PairingClient {
    http: reqwest::blocking::Client,
    url: String,
}

fn device_label() -> Option<String> {
    let from_file = |path: &str| {
        std::fs::read_to_string(path)
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    };
    from_file("/sys/devices/soc0/machine").or_else(|| from_file("/etc/hostname"))
}

#[derive(Debug, Clone, Deserialize)]
pub struct PairingStart {
    #[serde(rename = "userCode")]
    pub user_code: String,
    #[serde(rename = "deviceCode")]
    pub device_code: String,
    #[serde(rename = "verificationUrl")]
    pub verification_url: String,
    #[serde(rename = "verificationUrlComplete")]
    pub verification_url_complete: String,
    #[serde(rename = "expiresIn")]
    pub expires_in: u64,
    pub interval: u64,
}

#[derive(Debug, Clone)]
pub enum PairingStatus {
    Pending,
    Approved(String),
    Expired,
}

#[derive(Deserialize)]
struct PollResponse {
    status: String,
    token: Option<String>,
}

#[derive(Deserialize)]
struct ErrorResponse {
    error: String,
}

impl PairingClient {
    pub fn new(url: impl Into<String>) -> Self {
        Self {
            http: reqwest::blocking::Client::builder()
                .connect_timeout(CONNECT_TIMEOUT)
                .timeout(REQUEST_TIMEOUT)
                .build()
                .expect("building the Saver pairing HTTP client"),
            url: url.into(),
        }
    }

    fn call(&self, body: serde_json::Value) -> Result<serde_json::Value> {
        let response = self
            .http
            .post(&self.url)
            .json(&body)
            .send()
            .map_err(|err| {
                if err.is_timeout() || err.is_connect() {
                    anyhow::anyhow!("Could not reach Saver. Check your Wi-Fi and try again.")
                } else {
                    anyhow::anyhow!("Could not reach Saver: {err}")
                }
            })?;

        let status = response.status();
        let text = response.text().context("reading response body")?;

        if !status.is_success() {
            let message = serde_json::from_str::<ErrorResponse>(&text)
                .map(|e| e.error)
                .unwrap_or(text);
            bail!("pairing failed ({status}): {message}");
        }

        serde_json::from_str(&text).context("parsing response body")
    }

    pub fn start(&self) -> Result<PairingStart> {
        let value = self.call(json!({ "op": "start", "label": device_label() }))?;
        serde_json::from_value(value).context("parsing pairing start response")
    }

    pub fn poll(&self, user_code: &str, device_code: &str) -> Result<PairingStatus> {
        let value = self.call(json!({
            "op": "poll",
            "userCode": user_code,
            "deviceCode": device_code,
        }))?;
        let parsed: PollResponse =
            serde_json::from_value(value).context("parsing pairing poll response")?;

        match parsed.status.as_str() {
            "approved" => {
                let token = parsed
                    .token
                    .context("pairing was approved but no token was returned")?;
                Ok(PairingStatus::Approved(token))
            }
            "expired" => Ok(PairingStatus::Expired),
            _ => Ok(PairingStatus::Pending),
        }
    }
}

pub fn qr_matrix(data: &str) -> Result<serde_json::Value> {
    let code = QrCode::new(data.as_bytes()).context("encoding the pairing URL as a QR code")?;
    let modules: String = code
        .to_colors()
        .iter()
        .map(|color| if *color == Color::Dark { '1' } else { '0' })
        .collect();

    Ok(json!({ "size": code.width(), "modules": modules }))
}
