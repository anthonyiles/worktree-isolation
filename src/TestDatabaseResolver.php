<?php

declare(strict_types=1);

namespace WorktreeIsolation;

use InvalidArgumentException;
use PDO;
use PDOException;

class TestDatabaseResolver
{
    const int MAX_DERIVED_LENGTH = 40;

    /**
     * Derive a per-worktree test database name: "{base}_wt_{worktree}".
     *
     * @throws InvalidArgumentException
     */
    public static function derive(string $base, string $worktreeBasename): string
    {
        // The marker can't occur in an ordinary name, so a worktree's own
        // derived name can be stripped back to the base, and the result can
        // never be a database the main checkout uses.
        $base = explode(DevDatabaseResolver::MARKER, $base, 2)[0];

        if ($base === '') {
            throw new InvalidArgumentException('Cannot derive a per-worktree database name from an empty DB_DATABASE.');
        }

        // Checked on the base: a worktree named e.g. "test-refactor" must not
        // make a non-test base pass.
        if (! str_contains(strtolower($base), 'test')) {
            throw new InvalidArgumentException(
                "Database name \"$base\" does not contain \"test\". Refusing to proceed — this guard prevents accidental use of a non-test database."
            );
        }

        $derived = $base.DevDatabaseResolver::MARKER.self::worktreeSuffix($worktreeBasename);

        if (strlen($derived) > self::MAX_DERIVED_LENGTH) {
            throw new InvalidArgumentException(
                "Derived database name \"$derived\" exceeds the maximum length of ".self::MAX_DERIVED_LENGTH.' characters. Shorten your worktree directory name.'
            );
        }

        return $derived;
    }

    public static function worktreeSuffix(string $worktreeBasename): string
    {
        $suffix = preg_replace('/[^a-z0-9]+/', '-', strtolower($worktreeBasename)) ?? '';
        $suffix = trim($suffix, '-');

        return $suffix === '' ? 'worktree' : $suffix;
    }

    /**
     * Ensure the given database exists, creating it if necessary.
     *
     * @return bool Whether the database was created by this call.
     *
     * @throws InvalidArgumentException
     * @throws PDOException
     */
    public static function ensureExists(string $name, string $host, int $port, string $user, string $password): bool
    {
        if (preg_match('/^[a-z0-9_-]+$/', $name) !== 1) {
            throw new InvalidArgumentException(
                "Database name \"$name\" contains invalid characters. Only lowercase alphanumeric, hyphens and underscores are allowed."
            );
        }

        $dsn = "mysql:host=$host;port=$port";
        $pdo = new PDO($dsn, $user, $password, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        ]);

        $stmt = $pdo->prepare('SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = :name');
        $stmt->execute(['name' => $name]);

        if ($stmt->fetchColumn()) {
            return false;
        }

        try {
            $pdo->exec(sprintf('CREATE DATABASE `%s`', $name));
        } catch (PDOException $e) {
            if (($e->errorInfo[1] ?? null) !== 1007) {
                throw $e;
            }

            return false;
        }

        return true;
    }
}
