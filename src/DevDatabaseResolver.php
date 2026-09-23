<?php

declare(strict_types=1);

namespace WorktreeIsolation;

use InvalidArgumentException;

class DevDatabaseResolver
{
    const string MARKER = '_wt_';

    const int MAX_DERIVED_LENGTH = 64;

    /**
     * Derive a per-worktree development database name: "{base}_wt_{worktree}".
     *
     * @throws InvalidArgumentException
     */
    public static function derive(string $base, string $worktreeBasename): string
    {
        // A worktree's .env may already hold a derived name (setup re-run, or
        // the worktree was renamed), so always rebuild from the original base.
        $base = explode(self::MARKER, $base, 2)[0];

        if ($base === '') {
            throw new InvalidArgumentException('Cannot derive a per-worktree database name from an empty DB_DATABASE.');
        }

        $derived = $base.self::MARKER.TestDatabaseResolver::worktreeSuffix($worktreeBasename);

        if (strlen($derived) > self::MAX_DERIVED_LENGTH) {
            throw new InvalidArgumentException(
                "Derived database name \"$derived\" exceeds the maximum length of ".self::MAX_DERIVED_LENGTH.' characters. Shorten your worktree directory name.'
            );
        }

        return $derived;
    }

    public static function ensureExists(string $name, string $host, int $port, string $user, string $password): bool
    {
        return TestDatabaseResolver::ensureExists($name, $host, $port, $user, $password);
    }
}
