"""Isolate which part of the SSE generator blocks the stream."""
import os
import threading

os.environ.setdefault("BOOTSTRAP_ADMIN_PASSWORD", "x")

import anyio
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse

app = FastAPI()

# Reproduce the production middleware stack
from starlette.middleware.gzip import GZipMiddleware

app.add_middleware(GZipMiddleware, minimum_size=500)


async def gen_a():
    yield "event: a\ndata: {}\n\n"


async def gen_b(request: Request):
    if await request.is_disconnected():
        return
    yield "event: b\ndata: {}\n\n"


async def gen_c(request: Request):
    def _work():
        return 7

    count = await asyncio_to_thread(_work)
    yield f"event: c\ndata: {{\"n\": {count}}}\n\n"


async def asyncio_to_thread(fn):
    import asyncio

    return await asyncio.to_thread(fn)


@app.get("/a")
async def a():
    return StreamingResponse(gen_a(), media_type="text/event-stream")


@app.get("/b")
async def b(request: Request):
    return StreamingResponse(gen_b(request), media_type="text/event-stream")


@app.get("/c")
async def c(request: Request):
    return StreamingResponse(gen_c(request), media_type="text/event-stream")


async def main():
    import httpx

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        for name in ("a", "b", "c"):
            print(f"--- testing /{name}", flush=True)
            try:
                async def read_it():
                    with anyio.fail_after(5):
                        got = []
                        async with client.stream("GET", f"/{name}") as resp:
                            async for line in resp.aiter_lines():
                                got.append(line)
                                if len(got) >= 1:
                                    break
                        print(f"/{name} got: {got}", flush=True)

                await read_it()
            except TimeoutError:
                print(f"/{name} TIMEOUT", flush=True)


anyio.run(main)
print("done")
