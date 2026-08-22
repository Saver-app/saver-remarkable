use std::io;
use std::mem;

use anyhow::{Context, Result};

pub const MAX_MESSAGE_SIZE: usize = 10 * 1024 * 1024;
pub const MSG_SYSTEM_TERMINATE: u32 = 0xFFFF_FFFF;
pub const MSG_SYSTEM_NEW_COORDINATOR: u32 = 0xFFFF_FFFE;

pub struct Message {
    pub msg_type: u32,
    pub contents: String,
}

#[repr(C)]
struct Header {
    msg_type: u32,
    length: u32,
}

pub struct AppLoadSocket {
    fd: RawFdOwned,
}

struct RawFdOwned(libc::c_int);

impl Drop for RawFdOwned {
    fn drop(&mut self) {
        unsafe { libc::close(self.0) };
    }
}

impl AppLoadSocket {
    pub fn connect(socket_path: &str) -> Result<Self> {
        let fd = unsafe { libc::socket(libc::AF_UNIX, libc::SOCK_SEQPACKET, 0) };
        if fd < 0 {
            return Err(io::Error::last_os_error()).context("creating AppLoad socket");
        }
        let fd = RawFdOwned(fd);

        let mut addr: libc::sockaddr_un = unsafe { mem::zeroed() };
        addr.sun_family = libc::AF_UNIX as libc::sa_family_t;
        let path_bytes = socket_path.as_bytes();
        if path_bytes.len() >= addr.sun_path.len() {
            anyhow::bail!("AppLoad socket path too long: {socket_path}");
        }
        for (dst, &b) in addr.sun_path.iter_mut().zip(path_bytes) {
            *dst = b as libc::c_char;
        }

        let ret = unsafe {
            libc::connect(
                fd.0,
                &addr as *const _ as *const libc::sockaddr,
                mem::size_of::<libc::sockaddr_un>() as libc::socklen_t,
            )
        };
        if ret != 0 {
            return Err(io::Error::last_os_error())
                .with_context(|| format!("connecting to {socket_path}"));
        }

        Ok(Self { fd })
    }

    pub fn recv(&mut self) -> Result<Option<Message>> {
        let mut header = Header {
            msg_type: 0,
            length: 0,
        };
        let n = self
            .recv_retrying(
                &mut header as *mut _ as *mut libc::c_void,
                mem::size_of::<Header>(),
            )
            .context("reading AppLoad message header")?;
        if n == 0 {
            return Ok(None);
        }
        if n != mem::size_of::<Header>() as isize {
            anyhow::bail!(
                "AppLoad sent a short header ({n} of {} bytes)",
                mem::size_of::<Header>()
            );
        }

        let length = header.length as usize;
        if length > MAX_MESSAGE_SIZE {
            anyhow::bail!("AppLoad message of {length} bytes exceeds protocol limit");
        }

        let mut buf = vec![0u8; length.max(1)];
        let n = self
            .recv_retrying(buf.as_mut_ptr() as *mut libc::c_void, length)
            .context("reading AppLoad message payload")?;
        buf.truncate(n.max(0) as usize);
        let contents = String::from_utf8_lossy(&buf).into_owned();

        Ok(Some(Message {
            msg_type: header.msg_type,
            contents,
        }))
    }

    fn recv_retrying(&self, buf: *mut libc::c_void, len: usize) -> io::Result<isize> {
        loop {
            let n = unsafe { libc::recv(self.fd.0, buf, len, 0) };
            if n >= 0 {
                return Ok(n);
            }
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err);
        }
    }

    pub fn send(&mut self, msg_type: u32, contents: &str) -> Result<()> {
        let bytes = contents.as_bytes();
        let header = Header {
            msg_type,
            length: bytes.len() as u32,
        };
        self.send_retrying(
            &header as *const _ as *const libc::c_void,
            mem::size_of::<Header>(),
            "AppLoad message header",
        )?;

        if !bytes.is_empty() {
            self.send_retrying(
                bytes.as_ptr() as *const libc::c_void,
                bytes.len(),
                "AppLoad message payload",
            )?;
        }

        Ok(())
    }

    fn send_retrying(&self, buf: *const libc::c_void, len: usize, what: &str) -> Result<()> {
        loop {
            let n = unsafe { libc::send(self.fd.0, buf, len, 0) };
            if n >= 0 {
                return Ok(());
            }
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err).with_context(|| format!("sending {what}"));
        }
    }
}
