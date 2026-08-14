"""Tests for Railway / PaaS database URL normalization."""
import os
import unittest
from unittest import mock


class DatabaseUrlNormalizationTests(unittest.TestCase):
    def test_mysql_scheme_rewritten(self):
        from config import Config

        out = Config._normalize_database_url("mysql://user:pass@host:3306/railway")
        self.assertTrue(out.startswith("mysql+pymysql://"))
        self.assertIn("charset=utf8mb4", out)

    def test_existing_charset_preserved(self):
        from config import Config

        out = Config._normalize_database_url(
            "mysql+pymysql://user:pass@host:3306/db?charset=utf8mb4&foo=1"
        )
        self.assertIn("charset=utf8mb4", out)
        self.assertIn("foo=1", out)

    def test_port_prefers_railway_port(self):
        with mock.patch.dict(os.environ, {"PORT": "8080", "APP_PORT": "3001"}, clear=False):
            from config import _env

            self.assertEqual(int(_env("PORT", "APP_PORT", default="3001")), 8080)

    def test_validate_fails_without_db_on_railway(self):
        from config import Config

        with mock.patch.object(Config, "IS_PRODUCTION", True):
            with mock.patch.object(Config, "has_explicit_database_config", return_value=False):
                with self.assertRaises(RuntimeError) as ctx:
                    Config.validate_database_config()
                self.assertIn("DATABASE_URL", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
