<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Console\Command;
use Symfony\Component\Process\Process;

class InstallCommand extends Command
{
    protected $signature = 'worktree:install
        {--runtime= : Runtime driver: native, docker-compose, or docker-image (default: docker-image when Laravel Sail is detected, else native)}
        {--docker-image= : Docker image name (docker-image runtime)}
        {--docker-network= : Docker network name (docker-image runtime)}
        {--compose-service=app : Docker Compose service name (docker-compose runtime)}
        {--compose-project-base= : Docker Compose project base name (docker-compose runtime, default: derived from the project directory name)}
        {--test-command= : Test runner command (default: php artisan test)}
        {--force : Overwrite existing files}
        {--agents= : Add worktree instructions for AI agents (comma-separated files, default: existing AGENTS.md/CLAUDE.md, else AGENTS.md)}';

    protected $description = 'Install worktree isolation scripts, configuration, and git hooks';

    public function handle(): int
    {
        $args = [
            PHP_BINARY,
            dirname(__DIR__, 2).'/stubs/bin/worktree-install',
            '--project-dir='.base_path(),
            '--stubs-dir='.dirname(__DIR__, 2).'/stubs',
        ];

        if ($this->option('runtime')) {
            $args[] = '--runtime='.$this->option('runtime');
        }

        if ($this->option('docker-image')) {
            $args[] = '--docker-image='.$this->option('docker-image');
        }

        if ($this->option('docker-network')) {
            $args[] = '--docker-network='.$this->option('docker-network');
        }

        if ($this->option('compose-service') !== 'app') {
            $args[] = '--compose-service='.$this->option('compose-service');
        }

        if ($this->option('compose-project-base')) {
            $args[] = '--compose-project-base='.$this->option('compose-project-base');
        }

        if ($this->option('test-command')) {
            $args[] = '--test-command='.$this->option('test-command');
        }

        if ($this->option('force')) {
            $args[] = '--force';
        }

        if ($this->option('agents')) {
            $args[] = '--agents='.$this->option('agents');
        } elseif ($this->input->hasParameterOption('--agents')) {
            $args[] = '--agents';
        }

        $process = new Process($args, base_path());
        $process->setTimeout(120);

        $process->run(function (string $type, string $buffer): void {
            $this->output->write($buffer);
        });

        if (! $process->isSuccessful()) {
            return self::FAILURE;
        }

        $this->callSilently('vendor:publish', [
            '--tag' => 'worktree-isolation-config',
            '--force' => (bool) $this->option('force'),
        ]);

        return self::SUCCESS;
    }
}
