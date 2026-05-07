# OpenAlex Notes

PaperDaily fetches works from the OpenAlex `/works` endpoint.

## Polite Pool

OpenAlex recommends sending an email address through the `mailto` parameter. Configure it in one of these ways:

```bash
export OPENALEX_MAILTO="you@example.com"
```

or in `config.json`:

```python
"openalex": {
    "mailto": "you@example.com",
}
```

## API Key

If you have an OpenAlex API key, set:

```bash
export OPENALEX_API_KEY="..."
```

The environment variable name can be changed with `openalex.api_key_env`.

## Topic Filter

The default topic filter is:

```text
topics.field.id:17
```

This corresponds to Computer Science. You can narrow or broaden this by editing `openalex.topic_filter`.

## Fetch Strategy

PaperDaily first uses OpenAlex search queries per track, then applies local keyword filtering to reduce noisy matches. Keep OpenAlex queries broad enough to avoid missing relevant papers, and use local keywords for stricter domain relevance.
