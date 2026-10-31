<?php

declare(strict_types=1);

namespace WorktreeIsolation;

use InvalidArgumentException;
use PDO;
use PDOException;

/**
 * Per-worktree database names: "{base}_wt_{worktree}", at most the
 * subclass's MAX_DERIVED_LENGTH characters.
 */
abstract class WorktreeDatabaseResolver
{
    const MARKER = '_wt_';

    const HASH_LENGTH = 8;

    /**
     * @throws InvalidArgumentException
     */
    public static function derive(string $base, string $worktreeBasename): string
    {
        // The marker can't occur in an ordinary name, so a worktree's own
        // derived name (setup re-run, or the worktree was renamed) can be
        // stripped back to the base, and the result can never be a database
        // the main checkout uses.
        $base = explode(self::MARKER, $base, 2)[0];

        if ($base === '') {
            throw new InvalidArgumentException('Cannot derive a per-worktree database name from an empty DB_DATABASE.');
        }

        static::guard($base);

        return self::fit($base, self::worktreeSuffix($worktreeBasename), static::MAX_DERIVED_LENGTH);
    }

    /**
     * Rejects a base this kind of database must not be derived from.
     *
     * @throws InvalidArgumentException
     */
    protected static function guard(string $base): void
    {
    }

    /**
     * Join base and suffix, truncating an overlong suffix and appending a hash
     * of the full suffix so long worktree names sharing a prefix stay distinct.
     *
     * @throws InvalidArgumentException
     */
    public static function fit(string $base, string $suffix, int $maxLength): string
    {
        $derived = $base.self::MARKER.$suffix;

        if (strlen($derived) <= $maxLength) {
            return $derived;
        }

        $hash = substr(sha1($suffix), 0, self::HASH_LENGTH);
        $room = $maxLength - strlen($base.self::MARKER) - strlen($hash) - 1;

        if ($room < 1) {
            throw new InvalidArgumentException(
                "Database name \"$base\" is too long to derive a per-worktree name within $maxLength characters."
            );
        }

        return $base.self::MARKER.rtrim(substr($suffix, 0, $room), '-').'-'.$hash;
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
