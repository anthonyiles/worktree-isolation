<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class CleanDatabasesCommand extends Command
{
    protected $signature = 'worktree:clean
        {--force : Drop databases without confirmation}';

    protected $description = 'Drop all per-worktree test databases (testing-*)';

    public function handle(): int
    {
        $databases = DB::select(
            "SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE 'testing-%'"
        );

        if (empty($databases)) {
            $this->info('No per-worktree test databases found.');

            return self::SUCCESS;
        }

        $names = array_map(fn ($row) => $row->schema_name, $databases);

        $this->line('Found '.count($names).' per-worktree test database(s):');
        foreach ($names as $name) {
            $this->line("  - $name");
        }
        $this->newLine();

        if (! $this->option('force') && ! $this->confirm('Drop all of these databases?')) {
            $this->line('Aborted.');

            return self::SUCCESS;
        }

        foreach ($names as $name) {
            DB::statement("DROP DATABASE `$name`");
            $this->line("  Dropped: $name");
        }

        $this->newLine();
        $this->info('Done. '.count($names).' database(s) removed.');

        return self::SUCCESS;
    }
}
