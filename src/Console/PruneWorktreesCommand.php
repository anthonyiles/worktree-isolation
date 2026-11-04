<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Console\Command;

class PruneWorktreesCommand extends Command
{
    use RunsStubScript;

    protected $signature = 'worktree:prune
        {--dry-run : Only list the worktrees that would be removed}
        {--force : Remove them without confirmation}
        {--no-fetch : Use the local origin refs instead of fetching first}';

    protected $description = 'Remove merged worktrees with their Compose stacks and databases';

    public function handle(): int
    {
        $args = ['prune'];

        foreach (['dry-run', 'force', 'no-fetch'] as $flag) {
            if ($this->option($flag)) {
                $args[] = "--$flag";
            }
        }

        // A TTY lets the confirmation prompt read the answer.
        return $this->runStub('worktree', $args, timeout: 300, tty: true);
    }
}
