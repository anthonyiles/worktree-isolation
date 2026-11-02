<?php

declare(strict_types=1);

namespace WorktreeIsolation\Tests;

use Illuminate\Process\PendingProcess;
use Illuminate\Support\Facades\Process;
use PHPUnit\Framework\Attributes\Test;
use WorktreeIsolation\Console\InstallCommand;

class ConsoleCommandsTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        Process::fake();
    }

    #[Test]
    public function install_passes_only_the_project_and_stubs_dirs_by_default(): void
    {
        $this->artisan('worktree:install')->assertSuccessful();

        $this->assertRanStub('worktree-install', $this->installBaseArgs());
    }

    #[Test]
    public function install_forwards_the_options_it_was_given(): void
    {
        $this->artisan('worktree:install', [
            '--runtime' => 'docker-compose',
            '--compose-service' => 'web',
            '--test-command' => 'php vendor/bin/phpunit',
            '--force' => true,
            '--agents' => 'CLAUDE.md,AGENTS.md',
        ])->assertSuccessful();

        $this->assertRanStub('worktree-install', [
            ...$this->installBaseArgs(),
            '--runtime=docker-compose',
            '--compose-service=web',
            '--test-command=php vendor/bin/phpunit',
            '--force',
            '--agents=CLAUDE.md,AGENTS.md',
        ]);
    }

    #[Test]
    public function install_forwards_a_bare_agents_option(): void
    {
        $this->artisan('worktree:install', ['--agents' => null])->assertSuccessful();

        $this->assertRanStub('worktree-install', [...$this->installBaseArgs(), '--agents']);
    }

    #[Test]
    public function clean_runs_through_the_dispatcher_with_its_flags(): void
    {
        $this->artisan('worktree:clean', ['--force' => true, '--stale' => true])->assertSuccessful();

        $this->assertRanStub('worktree', ['clean', '--force', '--stale']);
    }

    #[Test]
    public function commands_fail_when_their_script_fails(): void
    {
        Process::fake(['*' => Process::result(exitCode: 1)]);

        $this->artisan('worktree:clean')->assertFailed();
        $this->artisan('worktree:install')->assertFailed();
    }

    /**
     * @return list<string>
     */
    private function installBaseArgs(): array
    {
        return ['--project-dir='.base_path(), '--stubs-dir='.InstallCommand::stubsDir()];
    }

    /**
     * @param  list<string>  $args
     */
    private function assertRanStub(string $script, array $args): void
    {
        $expected = ['bash', InstallCommand::stubsDir().'/bin/'.$script, ...$args];

        Process::assertRan(fn (PendingProcess $process) => $process->command === $expected && $process->path === base_path());
    }
}
