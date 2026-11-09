//! Git metadata for a session's working directory: the remote source and
//! worktree detection. The remote URL is read straight from `.git/config`
//! so no `git` subprocess is needed.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

#[derive(Debug, Clone, PartialEq)]
pub struct GitInfo {
    /// Raw remote URL (origin, or the first remote), when the repo has one.
    pub remote: Option<String>,
    /// Display key derived from the remote (`host/owner/repo`).
    pub remote_key: Option<String>,
    /// Path of the linked worktree when the cwd is one, else None.
    pub worktree: Option<PathBuf>,
}

static CACHE: Mutex<Option<HashMap<String, Option<GitInfo>>>> = Mutex::new(None);

/// Git metadata for `cwd`, cached per path. None when the directory is not
/// inside a git repository.
pub fn git_info(cwd: &str) -> Option<GitInfo> {
    {
        let cache = CACHE.lock().unwrap();
        if let Some(map) = cache.as_ref() {
            if let Some(value) = map.get(cwd) {
                return value.clone();
            }
        }
    }
    let info = compute_git_info(cwd);
    CACHE
        .lock()
        .unwrap()
        .get_or_insert_with(HashMap::new)
        .insert(cwd.to_string(), info.clone());
    info
}

fn compute_git_info(cwd: &str) -> Option<GitInfo> {
    let root = find_repo_root(Path::new(cwd))?;
    let git_path = root.join(".git");
    let (config_dir, worktree) = if git_path.is_file() {
        // A linked worktree: the .git file points at the main repo's
        // gitdir (<main>/.git/worktrees/<name>); the config is shared.
        let content = std::fs::read_to_string(&git_path).ok()?;
        let gitdir = content.trim().strip_prefix("gitdir:")?.trim();
        let gitdir = Path::new(gitdir);
        let main_git = gitdir.parent()?.parent()?;
        (main_git.to_path_buf(), Some(root.clone()))
    } else {
        (git_path, None)
    };
    let remote = read_remote_url(&config_dir.join("config"));
    Some(GitInfo {
        remote_key: remote.as_deref().and_then(normalize_remote),
        remote,
        worktree,
    })
}

/// Walk up from `start` to the nearest directory containing `.git`.
fn find_repo_root(start: &Path) -> Option<PathBuf> {
    let mut dir = if start.is_absolute() {
        start.to_path_buf()
    } else {
        std::env::current_dir().ok()?.join(start)
    };
    if !dir.is_dir() {
        dir = dir.parent()?.to_path_buf();
    }
    loop {
        if dir.join(".git").exists() {
            return Some(dir);
        }
        if !dir.pop() {
            return None;
        }
    }
}

/// The remote URL from a git config file: origin's url, else the first
/// remote's url.
fn read_remote_url(config: &Path) -> Option<String> {
    let text = std::fs::read_to_string(config).ok()?;
    let mut remotes: Vec<(String, String)> = Vec::new();
    let mut current_remote: Option<String> = None;
    for raw in text.lines() {
        let line = raw.trim();
        if line.starts_with('[') {
            current_remote = remote_section_name(line);
        } else if let Some(value) = line.strip_prefix("url") {
            if let Some(name) = &current_remote {
                let value = value.trim().trim_start_matches('=').trim();
                if !value.is_empty() {
                    remotes.push((name.clone(), value.to_string()));
                }
            }
        }
    }
    remotes
        .iter()
        .find(|(name, _)| name == "origin")
        .or_else(|| remotes.first())
        .map(|(_, url)| url.clone())
}

/// `[remote "origin"]` -> Some("origin"); any other section -> None.
fn remote_section_name(line: &str) -> Option<String> {
    let inner = line.trim_start_matches('[').trim_end_matches(']');
    if !inner.trim_start().starts_with("remote") {
        return None;
    }
    let name = inner.split('"').nth(1)?;
    Some(name.to_string())
}

/// Normalize a remote URL to a `host/owner/repo` display key:
/// `git@github.com:edjubert/miaou.git`, `https://github.com/edjubert/miaou.git`
/// and `ssh://git@github.com/edjubert/miaou` all become
/// `github.com/edjubert/miaou`.
pub fn normalize_remote(url: &str) -> Option<String> {
    let url = url.trim();
    if url.is_empty() {
        return None;
    }
    let (host, path) = if let Some((_, rest)) = url.split_once("://") {
        let (host, path) = rest.split_once('/').unwrap_or((rest, ""));
        (host.rsplit('@').next().unwrap_or(host), path)
    } else if let Some((user_host, path)) = url.split_once(':') {
        (user_host.rsplit('@').next().unwrap_or(user_host), path)
    } else {
        return None;
    };
    let path = path
        .trim_end_matches('/')
        .strip_suffix(".git")
        .unwrap_or(path.trim_end_matches('/'));
    if path.is_empty() {
        Some(host.to_string())
    } else {
        Some(format!("{host}/{path}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_remote_urls() {
        assert_eq!(
            normalize_remote("git@github.com:edjubert/miaou.git"),
            Some("github.com/edjubert/miaou".to_string())
        );
        assert_eq!(
            normalize_remote("https://github.com/edjubert/miaou.git"),
            Some("github.com/edjubert/miaou".to_string())
        );
        assert_eq!(
            normalize_remote("ssh://git@github.com/edjubert/miaou"),
            Some("github.com/edjubert/miaou".to_string())
        );
        assert_eq!(
            normalize_remote("https://gitlab.example.com/team/sub/proj/"),
            Some("gitlab.example.com/team/sub/proj".to_string())
        );
        assert_eq!(normalize_remote(""), None);
        assert_eq!(normalize_remote("no-scheme-no-colon"), None);
    }

    #[test]
    fn reads_origin_then_first_remote_from_config() {
        let tmp = tempfile::tempdir().unwrap();
        let config = tmp.path().join("config");
        std::fs::write(
            &config,
            "[core]\n\trepositoryformatversion = 0\n[remote \"upstream\"]\n\turl = https://example.com/up.git\n[remote \"origin\"]\n\turl = git@github.com:edjubert/miaou.git\n",
        )
        .unwrap();
        assert_eq!(
            read_remote_url(&config),
            Some("git@github.com:edjubert/miaou.git".to_string())
        );
        std::fs::write(
            &config,
            "[remote \"upstream\"]\n\turl = https://example.com/up.git\n",
        )
        .unwrap();
        assert_eq!(
            read_remote_url(&config),
            Some("https://example.com/up.git".to_string())
        );
        assert_eq!(read_remote_url(&tmp.path().join("missing")), None);
    }

    #[test]
    fn detects_repo_remote_and_worktree() {
        let tmp = tempfile::tempdir().unwrap();
        let repo = tmp.path().join("miaou");
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        std::fs::write(
            repo.join(".git/config"),
            "[remote \"origin\"]\n\turl = git@github.com:edjubert/miaou.git\n",
        )
        .unwrap();
        // A linked worktree of that repo.
        let wt = tmp.path().join("miaou-wt-feature");
        std::fs::create_dir_all(&wt).unwrap();
        let gitdir = repo.join(".git/worktrees/feature");
        std::fs::create_dir_all(&gitdir).unwrap();
        std::fs::write(wt.join(".git"), format!("gitdir: {}\n", gitdir.display())).unwrap();

        let main = git_info(repo.to_str().unwrap()).unwrap();
        assert_eq!(main.remote_key.as_deref(), Some("github.com/edjubert/miaou"));
        assert_eq!(main.worktree, None);

        let linked = git_info(wt.to_str().unwrap()).unwrap();
        assert_eq!(linked.remote_key.as_deref(), Some("github.com/edjubert/miaou"));
        assert_eq!(linked.worktree, Some(wt.clone()));

        // A subdirectory of the repo resolves to the same repo.
        let sub = repo.join("app/Sources");
        std::fs::create_dir_all(&sub).unwrap();
        let from_sub = git_info(sub.to_str().unwrap()).unwrap();
        assert_eq!(from_sub.remote_key.as_deref(), Some("github.com/edjubert/miaou"));

        // Not a repo.
        let plain = tmp.path().join("plain");
        std::fs::create_dir_all(&plain).unwrap();
        assert_eq!(git_info(plain.to_str().unwrap()), None);
        assert_eq!(git_info("/definitely/not/a/repo"), None);
    }
}
