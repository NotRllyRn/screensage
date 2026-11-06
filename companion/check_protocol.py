import asyncio, tempfile, json, sys
from pathlib import Path
sys.path.insert(0,'companion')
import server
from aiohttp import web
async def main():
 requests=[]
 async def handler(request):
  data=await request.json();requests.append(data)
  response={'id':'resp_test','object':'response','status':'completed','output':[{'id':'msg_test','type':'message','status':'completed','role':'assistant','content':[{'type':'output_text','text':'NOTE: synthetic','annotations':[]}]}],'usage':{'input_tokens':10,'output_tokens':5,'total_tokens':15}}
  events=[{'type':'response.created','response':{'id':'resp_test'}},{'type':'response.output_item.added','output_index':0,'item':response['output'][0]},{'type':'response.output_text.delta','item_id':'msg_test','output_index':0,'content_index':0,'delta':'NOTE: synthetic'},{'type':'response.output_item.done','output_index':0,'item':response['output'][0]},{'type':'response.completed','response':response}]
  return web.Response(text=''.join('data: '+json.dumps(e)+'\n\n' for e in events),content_type='text/event-stream')
 app=web.Application();app.router.add_post('/responses',handler)
 runner=web.AppRunner(app);await runner.setup();site=web.TCPSite(runner,'127.0.0.1',0);await site.start()
 port=site._server.sockets[0].getsockname()[1]
 old=server.config_args
 server.config_args=lambda:old()+['-c','model_provider="synthetic"','-c',f'model_providers.synthetic={{name="Synthetic",base_url="http://127.0.0.1:{port}",wire_api="responses",requires_openai_auth=false}}','-c','model="gpt-5.4"']
 try:
  with tempfile.TemporaryDirectory(prefix='screensage-wire-') as folder:
   home=Path(folder);(home/'empty').mkdir()
   async with server.RPC(home) as rpc:
    t=await rpc.call('thread/start',{'model':'gpt-5.4','ephemeral':True,'sandbox':'read-only','approvalPolicy':'never'})
    await rpc.call('turn/start',{'threadId':t['thread']['id'],'input':[{'type':'text','text':'Synthetic protocol check'}]})
    async with asyncio.timeout(30):
     while True:
      e=await rpc.events.get()
      if e['method']=='turn/completed':print('Native Codex mock turn:',e['params']['turn']['status']);break
    assert requests[0].get('tools', []) == [], 'Unexpected model-facing tools'
    print('Verified: no model-facing tools')
    print('Requests:',len(requests))
 finally:await runner.cleanup()
asyncio.run(main())
