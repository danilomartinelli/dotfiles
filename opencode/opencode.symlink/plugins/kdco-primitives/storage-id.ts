const SAFE_STORAGE_SEGMENT = /^[A-Za-z0-9][A-Za-z0-9_-]{0,255}$/;

/**
 * Validate an identifier before using it as a filesystem path segment.
 *
 * Session and delegation IDs originate outside the persistence layer. Keeping
 * them to one conservative segment prevents path traversal and makes the
 * storage boundary independent from upstream validation.
 */
export function assertSafeStorageSegment(
	value: string,
	label = "Storage identifier",
): string {
	const normalized = value.trim();
	if (!SAFE_STORAGE_SEGMENT.test(normalized)) {
		throw new Error(
			`${label} must contain only letters, numbers, underscores, and hyphens`,
		);
	}
	return normalized;
}

export function isSafeStorageSegment(value: string): boolean {
	return SAFE_STORAGE_SEGMENT.test(value.trim());
}
