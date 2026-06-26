<?php

declare(strict_types=1);

namespace WorktreeIsolation\Console;

use Illuminate\Console\Command;
use Symfony\Component\Process\Process;

class InstallCommand extends Command
{
    protected $signature = 'worktree:install
        {--runtime=native : Runtime driver: native, docker-compose, or docker-image}
        {--docker-image= : Docker image name (docker-image runtime)}
        {--docker-network= : Docker network name (docker-image runtime)}
        {--compose-service=app : Docker Compose service name (docker-compose runtime)}
        {--test-command= : Test runner command (default: php artisan test)}
        {--force : Overwrite existing files}';

    protected $description = 'Install worktree isolation scripts, configuration, and git hooks';

    public function handle(): int
    {
        $args = [
            PHP_BINARY,
            dirname(__DIR__, 2).'/stubs/bin/worktree-install',
            '--project-dir='.base_path(),
            '--stubs-dir='.dirname(__DIR__, 2).'/stubs',
            '--runtime='.$this->option('runtime'),
        ];

        if ($this->option('docker-image')) {
            $args[] = '--docker-image='.$this->option('docker-image');
        }

        if ($this->option('docker-network')) {
            $args[] = '--docker-network='.$this->option('docker-network');
        }

        if ($this->option('compose-service') !== 'app') {
            $args[] = '--compose-service='.$this->option('compose-service');
        }

        if ($this->option('test-command')) {
            $args[] = '--test-command='.$this->option('test-command');
        }

        if ($this->option('force')) {
            $args[] = '--force';
        }

        $process = new Process($args, base_path());
        $process->setTimeout(120);

        $process->run(function (string $type, string $buffer): void {
            $this->output->write($buffer);
        });

        if (! $process->isSuccessful()) {
            return self::FAILURE;
        }

        // Also publish the Laravel config file
        $this->callSilently('vendor:publish', [
            '--tag' => 'worktree-isolation-config',
            '--force' => (bool) $this->option('force'),
        ]);

        return self::SUCCESS;
    }
}
