"""Redis service for distributed rate limiting, caching, and locks.

Features graceful in-memory fallback when REDIS_URL is not configured or during local testing.
"""
from collections import defaultdict
import json
import os
import time
from typing import Any

REDIS_URL = os.environ.get("REDIS_URL")

_redis_client = None
if REDIS_URL:
    try:
        import redis
        _redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    except Exception as exc:
        print(f"[WARNING] Redis connection failed ({exc}), falling back to in-memory cache.")
        _redis_client = None


class _InMemoryStore:
    """Thread-safe fallback in-memory store with TTL support for local dev."""

    def __init__(self):
        self._store: dict[str, tuple[Any, float | None]] = {}
        self._rate_limits: dict[str, list[float]] = defaultdict(list)

    def get(self, key: str) -> str | None:
        if key not in self._store:
            return None
        val, expiry = self._store[key]
        if expiry and time.time() > expiry:
            del self._store[key]
            return None
        return val

    def set(self, key: str, value: str, ex: int | None = None) -> bool:
        expiry = (time.time() + ex) if ex else None
        self._store[key] = (value, expiry)
        return True

    def delete(self, key: str) -> bool:
        # Rate-limit windows live in their own map; deleting a rate-limit key must
        # clear that window too (mirrors Redis ZSET deletion semantics).
        existed = self._store.pop(key, None) is not None
        if self._rate_limits.pop(key, None) is not None:
            existed = True
        return existed

    def is_rate_limited(self, key: str, limit: int, window_seconds: int) -> bool:
        now = time.time()
        window_start = now - window_seconds
        attempts = [t for t in self._rate_limits[key] if t > window_start]
        if len(attempts) >= limit:
            return True
        attempts.append(now)
        self._rate_limits[key] = attempts
        return False


_fallback = _InMemoryStore()


class RedisService:
    @staticmethod
    def get(key: str) -> str | None:
        if _redis_client:
            try:
                return _redis_client.get(key)
            except Exception:
                pass
        return _fallback.get(key)

    @staticmethod
    def set(key: str, value: str | dict | list, ttl_seconds: int | None = None) -> bool:
        serialized = json.dumps(value) if isinstance(value, (dict, list)) else str(value)
        if _redis_client:
            try:
                return bool(_redis_client.set(key, serialized, ex=ttl_seconds))
            except Exception:
                pass
        return _fallback.set(key, serialized, ex=ttl_seconds)

    @staticmethod
    def delete(key: str) -> bool:
        if _redis_client:
            try:
                return bool(_redis_client.delete(key))
            except Exception:
                pass
        return _fallback.delete(key)

    @staticmethod
    def is_rate_limited(key: str, limit: int, window_seconds: int) -> bool:
        """Check if an action exceeds the rate limit in the current rolling window."""
        if _redis_client:
            try:
                pipe = _redis_client.pipeline()
                now = time.time()
                pipe.zremrangebyscore(key, 0, now - window_seconds)
                pipe.zadd(key, {str(now): now})
                pipe.zcard(key)
                pipe.expire(key, window_seconds + 5)
                _, _, count, _ = pipe.execute()
                return count > limit
            except Exception:
                pass
        return _fallback.is_rate_limited(key, limit, window_seconds)
