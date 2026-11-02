<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Console\Command;

class InstallCommand extends Command
{
    use RunsStubScript;

    protected $signature = 'worktree:install
        {--runtime= : Runtime driver: native, docker-compose, or docker-image (default: docker-image when Laravel Sail is detected, else native)}
        {--docker-image= : Docker image name (docker-image runtime)}
        {--docker-network= : Docker network name (docker-image runtime)}
        {--compose-service= : Docker Compose service name (docker-compose runtime, default: app)}
        {--compose-project-base= : Docker Compose project base name (docker-compose runtime, default: derived from the project directory name)}
        {--test-command= : Test runner command (default: php artisan test)}
        {--force : Overwrite existing files}
        {--agents= : Add worktree instructions for AI agents (comma-separated files, default: existing AGENTS.md/CLAUDE.md, else AGENTS.md)}';

    protected $description = 'Write .worktree-isolation.env and register the worktree setup git hook';

    /**
     * Options passed through as --name=value when given; the installer
     * applies the defaults.
     */
    private const VALUE_OPTIONS = ['runtime', 'docker-image', 'docker-network', 'compose-service', 'compose-project-base', 'test-command'];

    public function handle(): int
    {
        $args = ['--project-dir='.base_path(), '--stubs-dir='.self::stubsDir()];

        foreach (self::VALUE_OPTIONS as $option) {
            if ($this->option($option)) {
                $args[] = "--$option=".$this->option($option);
            }
        }

        if ($this->option('force')) {
            $args[] = '--force';
        }

        if ($this->option('agents')) {
            $args[] = '--agents='.$this->option('agents');
        } elseif ($this->input->hasParameterOption('--agents')) {
            $args[] = '--agents';
        }

        return $this->runStub('worktree-install', $args, timeout: 120);
    }
}
