<?php

declare(strict_types=1);

namespace WorktreeIsolation\Tests;

use Illuminate\Support\Facades\Artisan;
use PHPUnit\Framework\Attributes\Test;

class WorktreeIsolationServiceProviderTest extends TestCase
{
    #[Test]
    public function it_registers_the_worktree_console_commands(): void
    {
        $this->assertArrayHasKey('worktree:install', Artisan::all());
        $this->assertArrayHasKey('worktree:clean', Artisan::all());
    }
}
