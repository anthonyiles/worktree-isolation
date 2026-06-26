<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Console\Command;
use Illuminate\Filesystem\Filesystem;

class InstallCommand extends Command
{
    protected $signature = 'worktree:install
        {--docker-image= : The Sail Docker image name (e.g. sail-8.5/app)}
        {--docker-network= : The Docker network name (e.g. myapp_sail)}
        {--force : Overwrite existing files}';

    protected $description = 'Install worktree isolation scripts and configuration';

    public function handle(Filesystem $files): int
    {
        $basePath = base_path();
        $stubPath = dirname(__DIR__, 2).'/stubs';
        $force = (bool) $this->option('force');

        $this->info('Installing worktree isolation...');

        // Publish config
        $this->call('vendor:publish', [
            '--tag' => 'worktree-isolation-config',
            '--force' => $force,
        ]);

        // Create bin directory
        $files->ensureDirectoryExists("$basePath/bin");

        // Copy bin/worktree-setup
        $this->publishFile(
            $files,
            "$stubPath/bin/worktree-setup",
            "$basePath/bin/worktree-setup",
            $force
        );

        // Copy bin/test
        $this->publishFile(
            $files,
            "$stubPath/bin/test",
            "$basePath/bin/test",
            $force
        );

        // Create .githooks directory and copy hook
        $files->ensureDirectoryExists("$basePath/.githooks");

        $this->publishFile(
            $files,
            "$stubPath/githooks/post-checkout-worktree-setup.sh",
            "$basePath/.githooks/post-checkout-worktree-setup.sh",
            $force
        );

        // Make scripts executable
        chmod("$basePath/bin/worktree-setup", 0755);
        chmod("$basePath/bin/test", 0755);
        chmod("$basePath/.githooks/post-checkout-worktree-setup.sh", 0755);

        // Create .worktree-isolation.env configuration
        $this->createEnvConfig($basePath, $force);

        // Create/update .githooks.config with the post-checkout hook
        $this->ensureGitHookConfig($basePath, $files);

        $this->newLine();
        $this->info('Worktree isolation installed successfully!');
        $this->newLine();
        $this->line('Next steps:');
        $this->line('  1. Edit <comment>.worktree-isolation.env</comment> with your Docker image and network names');
        $this->line('  2. Run <comment>make setup-worktree-hooks</comment> to enable the git hook');
        $this->line('  3. Add <comment>.worktree-isolation.env</comment> to your <comment>.gitignore</comment> if it contains secrets');
        $this->newLine();

        return self::SUCCESS;
    }

    private function publishFile(Filesystem $files, string $from, string $to, bool $force): void
    {
        if ($files->exists($to) && ! $force) {
            $this->warn("  Skipping: $to (already exists, use --force to overwrite)");

            return;
        }

        $files->copy($from, $to);
        $this->line("  Published: $to");
    }

    private function createEnvConfig(string $basePath, bool $force): void
    {
        $envFile = "$basePath/.worktree-isolation.env";

        if (file_exists($envFile) && ! $force) {
            $this->warn("  Skipping: .worktree-isolation.env (already exists)");

            return;
        }

        $image = $this->option('docker-image') ?: 'sail-8.4/app';
        $network = $this->option('docker-network') ?: basename($basePath).'_sail';

        $content = <<<ENV
        # Worktree Isolation Configuration
        # These values are used by bin/worktree-setup and bin/test

        WORKTREE_DOCKER_IMAGE=$image
        WORKTREE_DOCKER_NETWORK=$network
        WORKTREE_TESTING_ENV_FILE=.env.testing
        WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example
        WORKTREE_DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE

        # Additional env vars to pass to the test container (space-separated)
        # WORKTREE_EXTRA_ENV_VARS=PENNANT_STORE MAILGUN_WEBHOOK_SIGNING_KEY
        ENV;

        file_put_contents($envFile, $content."\n");
        $this->line("  Created: .worktree-isolation.env");
    }

    private function ensureGitHookConfig(string $basePath, Filesystem $files): void
    {
        $configFile = "$basePath/.githooks.config";
        $hookEntry = <<<'CONFIG'

        [hook "worktree-setup"]
            event = post-checkout
            command = .githooks/post-checkout-worktree-setup.sh
        CONFIG;

        if ($files->exists($configFile)) {
            $content = $files->get($configFile);
            if (str_contains($content, 'worktree-setup')) {
                return;
            }
            $files->append($configFile, "\n".$hookEntry."\n");
            $this->line('  Updated: .githooks.config (added worktree-setup hook)');
        } else {
            $content = <<<'CONFIG'
            # Git Hooks Configuration
            # Include this in your local git config:
            #   git config --local include.path ../.githooks.config

            CONFIG;
            $files->put($configFile, $content.$hookEntry."\n");
            $this->line('  Created: .githooks.config');
        }
    }
}
