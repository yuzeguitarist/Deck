use anyhow::Result;
use deckclip_core::DeckClient;

use crate::cli::{AiAction, AiCommand, AiRunArgs, AiSearchArgs, AiTransformArgs};
use crate::output::{read_text_or_stdin, OutputMode};

pub async fn run(client: &mut DeckClient, output: OutputMode, cmd: AiCommand) -> Result<()> {
    match cmd.action {
        AiAction::Run(args) => run_ai(client, output, args).await,
        AiAction::Search(args) => search(client, output, args).await,
        AiAction::Transform(args) => transform(client, output, args).await,
    }
}

async fn run_ai(client: &mut DeckClient, output: OutputMode, args: AiRunArgs) -> Result<()> {
    // If --text is not provided, try reading from stdin
    let text = if args.text.is_some() {
        args.text
    } else {
        read_text_or_stdin(None).ok()
    };

    let response = client
        .ai_run(
            &args.prompt,
            text.as_deref(),
            args.save,
            args.tag_id.as_deref(),
        )
        .await?;
    output.print_response(&response);
    Ok(())
}

async fn search(client: &mut DeckClient, output: OutputMode, args: AiSearchArgs) -> Result<()> {
    let response = client
        .ai_search(&args.query, args.mode.as_deref(), Some(args.limit))
        .await?;
    output.print_response(&response);
    Ok(())
}

async fn transform(
    client: &mut DeckClient,
    output: OutputMode,
    args: AiTransformArgs,
) -> Result<()> {
    // If --text is not provided, try reading from stdin
    let text = if args.text.is_some() {
        args.text
    } else {
        read_text_or_stdin(None).ok()
    };

    let response = client
        .ai_transform(&args.prompt, text.as_deref(), args.plugin.as_deref())
        .await?;
    output.print_response(&response);
    Ok(())
}
