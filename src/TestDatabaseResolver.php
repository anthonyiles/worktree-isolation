<?php

declare(strict_types=1);

namespace WorktreeIsolation;

use InvalidArgumentException;

class TestDatabaseResolver extends WorktreeDatabaseResolver
{
    const MAX_DERIVED_LENGTH = 40;

    /**
     * Checked on the base: a worktree named e.g. "test-refactor" must not
     * make a non-test base pass.
     */
    protected static function guard(string $base): void
    {
        if (! str_contains(strtolower($base), 'test')) {
            throw new InvalidArgumentException(
                "Database name \"$base\" does not contain \"test\". Refusing to proceed — this guard prevents accidental use of a non-test database."
            );
        }
    }
}
