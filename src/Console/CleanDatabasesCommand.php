<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Console\Command;

class CleanDatabasesCommand extends Command
{
    use RunsStubScript;

    protected $signature = 'worktree:clean
        {--force : Drop databases without confirmation}
        {--stale : Only drop databases whose worktree no longer exists}';

    protected $description = 'Drop per-worktree test and development databases';

    public function handle(): int
    {
        $args = ['clean'];

        foreach (['force', 'stale'] as $flag) {
            if ($this->option($flag)) {
                $args[] = "--$flag";
            }
        }

        // Through vendor/bin/worktree, so the Docker runtimes run clean in
        // their container, where DB_HOST (e.g. "mysql") resolves. A TTY lets
        // the confirmation prompt read the answer.
        return $this->runStub('worktree', $args, timeout: 60, tty: true);
    }
}
