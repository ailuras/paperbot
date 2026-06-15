"""Tests for DeepSeek translation module."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from paperbot.translate import translate_paper, translate_text


@pytest.fixture(autouse=True)
def deepseek_api_key(monkeypatch):
    """Give translation tests a fake API key; HTTP calls are mocked."""
    monkeypatch.setenv("DEEPSEEK_API_KEY", "test-key")


def test_translate_paper_success():
    """translate_paper calls DeepSeek API and returns TranslationResult."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "choices": [
            {"message": {"content": "  测试标题  "}}
        ]
    }
    mock_response.raise_for_status = MagicMock()

    with patch("paperbot.translate.httpx.post", return_value=mock_response):
        result = translate_paper("Test Title", "Test abstract.")

    assert result.title_zh == "测试标题"
    assert result.abstract_zh == "测试标题"  # same mock response for both calls
    assert result.source == "api"


def test_translate_paper_empty_abstract():
    """translate_paper skips abstract translation if abstract is empty."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "choices": [{"message": {"content": "测试标题"}}]
    }
    mock_response.raise_for_status = MagicMock()

    call_count = 0

    def counting_post(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        return mock_response

    with patch("paperbot.translate.httpx.post", side_effect=counting_post):
        result = translate_paper("Test Title", "")

    assert call_count == 1  # Only title translated
    assert result.abstract_zh == ""


def test_translate_paper_none_abstract():
    """translate_paper skips abstract translation if abstract is None."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "choices": [{"message": {"content": "测试标题"}}]
    }
    mock_response.raise_for_status = MagicMock()

    call_count = 0

    def counting_post(*args, **kwargs):
        nonlocal call_count
        call_count += 1
        return mock_response

    with patch("paperbot.translate.httpx.post", side_effect=counting_post):
        result = translate_paper("Test Title", None)

    assert call_count == 1
    assert result.abstract_zh == ""


def test_translate_text():
    """translate_text translates arbitrary text."""
    mock_response = MagicMock()
    mock_response.json.return_value = {
        "choices": [{"message": {"content": "  你好世界  "}}]
    }
    mock_response.raise_for_status = MagicMock()

    with patch("paperbot.translate.httpx.post", return_value=mock_response):
        result = translate_text("Hello World", target_language="中文")

    assert result == "你好世界"


def test_translate_api_error():
    """translate_paper raises on API error."""
    mock_response = MagicMock()
    mock_response.raise_for_status.side_effect = Exception("API Error")

    with patch("paperbot.translate.httpx.post", return_value=mock_response):
        try:
            translate_paper("Test")
            assert False, "Should have raised"
        except Exception as e:
            assert "API Error" in str(e)


def test_translate_uses_correct_model():
    """Verify the correct model is passed in the payload."""
    captured = {}

    def capture_post(url, headers=None, json=None, timeout=None):
        captured["payload"] = json
        mock = MagicMock()
        mock.json.return_value = {"choices": [{"message": {"content": "x"}}]}
        mock.raise_for_status = MagicMock()
        return mock

    with patch("paperbot.translate.httpx.post", side_effect=capture_post):
        translate_paper("Title", "Abstract")

    assert captured["payload"]["model"] == "deepseek-v4-flash"
    assert captured["payload"]["temperature"] == 0.3
    assert len(captured["payload"]["messages"]) == 2
    assert captured["payload"]["messages"][0]["role"] == "system"
    assert captured["payload"]["messages"][1]["role"] == "user"


def test_translate_reads_api_key_at_call_time(monkeypatch):
    """Changing DEEPSEEK_API_KEY after import affects the next API call."""
    captured = {}

    def capture_post(url, headers=None, json=None, timeout=None):
        captured["headers"] = headers
        mock = MagicMock()
        mock.json.return_value = {"choices": [{"message": {"content": "x"}}]}
        mock.raise_for_status = MagicMock()
        return mock

    monkeypatch.setenv("DEEPSEEK_API_KEY", "runtime-key")

    with patch("paperbot.translate.httpx.post", side_effect=capture_post):
        translate_text("Hello")

    assert captured["headers"]["Authorization"] == "Bearer runtime-key"
