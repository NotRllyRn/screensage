import asyncio
import base64
import tempfile
import unittest
from pathlib import Path
from aiohttp.test_utils import TestClient, TestServer
from server import analyze, validate_analysis, make_app, config_args

IMAGE = 'data:image/jpeg;base64,' + base64.b64encode(b'\xff\xd8\xfftest').decode()
DATA = {'model': 'vision', 'prompt': 'Synthetic test', 'image': IMAGE}

class FakeRPC:
    def __init__(self, status='completed'):
        self.calls = []
        self.events = asyncio.Queue()
        self.events.put_nowait({'method': 'item/completed', 'params': {'threadId': 't', 'item': {'type': 'agentMessage', 'text': 'NOTE: blue'}}})
        self.events.put_nowait({'method': 'turn/completed', 'params': {'threadId': 't', 'turn': {'id': 'u', 'status': status}}})
    async def call(self, method, params):
        self.calls.append((method, params))
        return {'account/read': {'account': {'type': 'chatgpt'}}, 'model/list': {'data': [{'model': 'vision', 'inputModalities': ['image']}]}, 'thread/start': {'thread': {'id': 't'}}, 'turn/start': {'turn': {'id': 'u'}}}.get(method, {})

class Tests(unittest.IsolatedAsyncioTestCase):
    def test_validate_rejects_url_and_oversized_prompt(self):
        self.assertEqual(validate_analysis(DATA), DATA)
        for change in ({'image': 'https://example.com/image.jpg'}, {'prompt': 'x' * 16001}, {'image': 'data:image/jpeg;base64,not-valid'}):
            with self.assertRaises(ValueError): validate_analysis(DATA | change)
    def test_commands_and_connectors_disabled(self):
        args = config_args()
        for setting in ('features.shell_tool=false', 'features.unified_exec=false', 'features.apps=false', 'features.code_mode=false'):
            self.assertIn(setting, args)
    async def test_images_sent_to_ephemeral_thread_and_turn_completed(self):
        rpc = FakeRPC(); result = await analyze(rpc, DATA)
        self.assertEqual(result, {'text': 'NOTE: blue', 'threadId': 't'})
        self.assertTrue(dict(rpc.calls)['thread/start']['ephemeral'])
        self.assertEqual(dict(rpc.calls)['turn/start']['input'][1], {'type': 'image', 'url': IMAGE})
        self.assertEqual(rpc.calls[-1][0], 'turn/interrupt')
    async def test_incomplete_turn_is_failure(self):
        with self.assertRaises(RuntimeError): await analyze(FakeRPC('failed'), DATA)
    async def test_cancel_interrupts_turn(self):
        rpc = FakeRPC(); rpc.events = asyncio.Queue()
        task = asyncio.create_task(analyze(rpc, DATA)); await asyncio.sleep(0)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError): await task
        self.assertEqual(rpc.calls[-1][0], 'turn/interrupt')
    async def test_http_auth_and_origin_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            client = TestClient(TestServer(make_app(Path(folder), 'x' * 32)))
            await client.start_server()
            try:
                response = await client.post('/analyze', json=DATA)
                self.assertEqual(response.status, 401)
                response = await client.post('/analyze', json=DATA, headers={'Authorization': 'Bearer ' + 'x' * 32, 'Origin': 'https://example.com'})
                self.assertEqual(response.status, 403)
            finally: await client.close()

if __name__ == '__main__': unittest.main()
