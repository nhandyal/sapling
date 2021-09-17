/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This software may be used and distributed according to the terms of the
 * GNU General Public License version 2.
 */

use std::sync::Arc;

use anyhow::{anyhow, Error};
use clap::{value_t, App, Arg, ArgMatches, SubCommand};
use cmdlib::args::{self, MononokeMatches};
use context::CoreContext;
use context::SessionContainer;
use fbinit::FacebookInit;
use maplit::hashmap;
use megarepo_api::MegarepoApi;
use mononoke_types::ChangesetId;
use mononoke_types::Timestamp;
use prettytable::{cell, format, row, Table};
use slog::Logger;

use crate::error::SubcommandError;

use async_requests::types::{RequestStatus, RowId, ThriftMegarepoAsynchronousRequestParams};
use mononoke_api::{
    BookmarkUpdateDelay, Mononoke, MononokeApiEnvironment, WarmBookmarksCacheDerivedData,
};
use repo_factory::RepoFactory;

pub const ASYNC_REQUESTS: &str = "async-requests";
const LIST_CMD: &str = "list";
pub const LOOKBACK_SECS: &str = "lookback";

const SHOW_CMD: &str = "show";
pub const REQUEST_ID_ARG: &str = "request-id";

pub fn build_subcommand<'a, 'b>() -> App<'a, 'b> {
    let list = SubCommand::with_name(LIST_CMD)
         .about(
             "lists asynchronous requests (by default the ones active now or updated within last 5 mins)",
         ).arg(Arg::with_name(LOOKBACK_SECS)
            .long(LOOKBACK_SECS)
            .value_name("N")
            .help("limit the results to the requests updated in the last N seconds")
            .default_value("3600")
            .takes_value(true)
        );

    let show = SubCommand::with_name(SHOW_CMD)
        .about("shows request details")
        .arg(
            Arg::with_name(REQUEST_ID_ARG)
                .value_name("ID")
                .help("id of the request")
                .takes_value(true),
        );

    SubCommand::with_name(ASYNC_REQUESTS)
        .about("view and manage the SCS async requests (used by megarepo)")
        .subcommand(list)
        .subcommand(show)
}

pub async fn subcommand_async_requests<'a>(
    fb: FacebookInit,
    logger: Logger,
    matches: &'a MononokeMatches<'a>,
    sub_m: &'a ArgMatches<'a>,
) -> Result<(), SubcommandError> {
    let config_store = matches.config_store();
    let (repo_name, repo_config) = args::get_config(config_store, matches)?;
    let common_config = args::load_common_config(config_store, &matches)?;
    let repo_configs = args::RepoConfigs {
        repos: hashmap! {
            repo_name => repo_config
        },
        common: common_config,
    };
    let repo_factory = RepoFactory::new(matches.environment().clone(), &repo_configs.common);
    let env = MononokeApiEnvironment {
        repo_factory: repo_factory.clone(),
        disabled_hooks: Default::default(),
        warm_bookmarks_cache_derived_data: WarmBookmarksCacheDerivedData::None,
        warm_bookmarks_cache_delay: BookmarkUpdateDelay::Disallow,
        skiplist_enabled: false,
        warm_bookmarks_cache_enabled: false,
    };
    let mononoke = Arc::new(Mononoke::new(&env, repo_configs.clone()).await?);
    let megarepo = MegarepoApi::new(matches.environment(), repo_configs, repo_factory, mononoke)
        .await
        .map_err(Error::new)?;
    let session = SessionContainer::new_with_defaults(fb);
    let ctx = session.new_context(logger.clone(), matches.scuba_sample_builder());
    match sub_m.subcommand() {
        (LIST_CMD, Some(sub_m)) => handle_list(sub_m, ctx, megarepo).await?,
        (SHOW_CMD, Some(sub_m)) => handle_show(sub_m, ctx, megarepo).await?,
        _ => return Err(SubcommandError::InvalidArgs),
    }
    Ok(())
}

async fn handle_list(
    args: &ArgMatches<'_>,
    ctx: CoreContext,
    megarepo: MegarepoApi,
) -> Result<(), Error> {
    let repos_and_queues = megarepo.all_async_method_request_queues(&ctx).await?;

    let lookback = value_t!(args.value_of(LOOKBACK_SECS), i64)?;

    let mut table = Table::new();
    table.set_titles(row![
        "Request id",
        "Method",
        "Status",
        "Target bookmark",
        "Source name (sync_changeset)",
        "Source Changeset (sync_changeset)"
    ]);
    for (repo_ids, queue) in repos_and_queues {
        let res = queue
            .list_requests(
                &ctx,
                &repo_ids,
                &[
                    RequestStatus::New,
                    RequestStatus::InProgress,
                    RequestStatus::Ready,
                    RequestStatus::Polled,
                ],
                Some(&Timestamp::from_timestamp_secs(
                    Timestamp::now().timestamp_seconds() - lookback,
                )),
            )
            .await?;
        for (req_id, entry, params) in res.into_iter() {
            let (source_name, changeset_id) = match params.thrift() {
                ThriftMegarepoAsynchronousRequestParams::megarepo_sync_changeset_params(params) => {
                    (
                        params.source_name.clone(),
                        ChangesetId::from_bytes(params.cs_id.clone())?.to_string(),
                    )
                }
                _ => ("".to_string(), "".to_string()),
            };
            table.add_row(row![
                req_id.0,
                req_id.1,
                entry.status,
                params.target()?.bookmark,
                &source_name,
                &changeset_id
            ]);
        }
    }
    table.set_format(*format::consts::FORMAT_NO_LINESEP_WITH_TITLE);
    table.printstd();

    Ok(())
}

async fn handle_show(
    args: &ArgMatches<'_>,
    ctx: CoreContext,
    megarepo: MegarepoApi,
) -> Result<(), Error> {
    let repos_and_queues = megarepo.all_async_method_request_queues(&ctx).await?;

    let row_id = value_t!(args.value_of(REQUEST_ID_ARG), u64)?;

    for (_repo_ids, queue) in repos_and_queues {
        if let Some((_request_id, entry, params, maybe_result)) =
            queue.get_request_by_id(&ctx, &RowId(row_id)).await?
        {
            // TODO: pretty printing of the request details
            dbg!(entry, params, maybe_result);
            return Ok(());
        }
    }
    Err(anyhow!("Request not found."))
}
