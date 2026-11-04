<?php

declare(strict_types=1);

namespace WorktreeIsolation;

/**
 * Setup calls ensureExists() through this class with the worktree's own
 * autoloader, which may hold an older release, so the class must stay.
 */
class TestDatabaseResolver extends WorktreeDatabaseResolver
{
}
