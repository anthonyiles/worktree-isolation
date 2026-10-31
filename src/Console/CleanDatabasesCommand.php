<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Console\Command;
use Symfony\Component\Process\Process;

class CleanDatabasesCommand extends Command
{
    protected $signature = 'worktree:clean
        {--force : Drop databases without confirmation}';

    protected $description = 'Drop all per-worktree test databases';

    public function handle(): int
    {
        // Through vendor/bin/worktree, so the Docker runtimes run clean in
        // their container, where DB_HOST (e.g. "mysql") resolves.
        $args = ['bash', dirname(__DIR__, 2).'/stubs/bin/worktree', 'clean'];

        if ($this->option('force')) {
            $args[] = '--force';
        }

        $process = new Process($args, base_path());
        $process->setTimeout(60);
        $process->setTty(Process::isTtySupported());

        $process->run(function (string $type, string $buffer): void {
            $this->output->write($buffer);
        });

        return $process->isSuccessful() ? self::SUCCESS : self::FAILURE;
    }
}
