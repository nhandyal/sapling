/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This software may be used and distributed according to the terms of the
 * GNU General Public License version 2.
 */

use anyhow::Result;
use clap::Args;
use context::CoreContext;
use repo_identity::RepoIdentityRef;
use repo_lock::RepoLockRef;
use repo_lock::RepoLockState;

use super::Repo;

#[derive(Args)]
pub struct RepoLockArgs {
    /// Why is the repo being locked
    #[clap(long)]
    reason: String,
}

pub async fn repo_lock(_ctx: &CoreContext, repo: &Repo, args: RepoLockArgs) -> Result<()> {
    let RepoLockArgs { reason } = args;
    repo.repo_lock()
        .set_repo_lock(RepoLockState::Locked(reason))
        .await?;
    println!("Repo locked :)");
    Ok(())
}

#[derive(Args)]
pub struct RepoUnlockArgs {}

pub async fn repo_unlock(_ctx: &CoreContext, repo: &Repo, args: RepoUnlockArgs) -> Result<()> {
    let RepoUnlockArgs {} = args;
    repo.repo_lock()
        .set_repo_lock(RepoLockState::Unlocked)
        .await?;
    println!("Repo unlocked :)");
    Ok(())
}

#[derive(Args)]
pub struct RepoShowLockArgs {}

pub async fn repo_show_lock(_ctx: &CoreContext, repo: &Repo, args: RepoShowLockArgs) -> Result<()> {
    let RepoShowLockArgs {} = args;
    let state = repo.repo_lock().check_repo_lock().await?;
    let state = match state {
        RepoLockState::Unlocked => "unlocked".to_string(),
        RepoLockState::Locked(reason) => format!("locked with reason: {}", reason),
    };
    println!("{} is {}", repo.repo_identity().name(), state);
    println!("Consider using `newadmin repos show-locks` to see locks on all repos");
    Ok(())
}
