<?php

declare(strict_types=1);

namespace WorktreeIsolation\Tests;

use InvalidArgumentException;
use PHPUnit\Framework\TestCase;
use WorktreeIsolation\DevDatabaseResolver;
use WorktreeIsolation\TestDatabaseResolver;

class DatabaseResolverTest extends TestCase
{
    public function test_test_database_derivation_is_idempotent(): void
    {
        $derived = TestDatabaseResolver::derive('testing', 'Feature/Auth');

        $this->assertSame('testing_wt_feature-auth', $derived);
        $this->assertSame($derived, TestDatabaseResolver::derive($derived, 'Feature/Auth'));
    }

    public function test_test_database_never_resolves_to_the_base(): void
    {
        $this->assertSame('app-testing_wt_testing', TestDatabaseResolver::derive('app-testing', 'testing'));
    }

    public function test_dev_database_is_derived_with_marker(): void
    {
        $this->assertSame('myapp_wt_feature-auth', DevDatabaseResolver::derive('myapp', 'Feature/Auth'));
    }

    public function test_dev_database_rederives_from_original_base(): void
    {
        $this->assertSame('myapp_wt_feature-auth', DevDatabaseResolver::derive('myapp_wt_feature-auth', 'feature-auth'));
        $this->assertSame('myapp_wt_renamed', DevDatabaseResolver::derive('myapp_wt_feature-auth', 'renamed'));
    }

    public function test_dev_database_rejects_overlong_names(): void
    {
        $this->expectException(InvalidArgumentException::class);

        DevDatabaseResolver::derive('myapp', str_repeat('a', 64));
    }

    public function test_test_database_requires_test_in_the_base_not_the_worktree_name(): void
    {
        $this->expectException(InvalidArgumentException::class);

        TestDatabaseResolver::derive('laravel', 'test-refactor');
    }
}
