vim.opt.rtp:prepend(vim.fn.getcwd())
local originals, passed = {}, 0
local function mock(name, value)
  if originals[name] == nil then originals[name] = package.loaded[name] or false end
  package.loaded[name] = value
end
local function restore()
  for name, value in pairs(originals) do package.loaded[name] = value or nil end
  originals = {}
end
local function eq(a, b) assert(vim.deep_equal(a, b), vim.inspect(a) .. ' != ' .. vim.inspect(b)) end
local function wait(predicate) assert(vim.wait(3000, predicate, 5), 'wait timed out') end
local function test(name, body)
  body(); restore(); require('opvi.state').clear(); passed = passed + 1; print('PASS ' .. name)
end

local function main()
  require('opvi').setup()
  for _, file in ipairs(vim.fn.glob('lua/**/*.lua', false, true)) do assert(loadfile(file)) end
  test('UTF-8 character, emoji, exclusive, reverse, and tab block selection', function()
    local C = require('opvi.context')
    local function capture(lines, first, last, mode, exclusive)
      vim.cmd('enew!')
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.o.selection = exclusive and 'exclusive' or 'inclusive'
      vim.api.nvim_win_set_cursor(0, first)
      vim.cmd('normal! ' .. mode)
      vim.api.nvim_win_set_cursor(0, last)
      return C.capture()
    end
    local c = capture({ 'á🙂z' }, { 1, 0 }, { 1, 0 }, 'v')
    eq(c.selection_text, 'á'); assert(c:render('@this'):find('á', 1, true)); c:clear()
    c = capture({ 'á🙂z' }, { 1, 2 }, { 1, 2 }, 'v')
    eq(c.selection_text, '🙂'); c:clear()
    c = capture({ 'á🙂z' }, { 1, 0 }, { 1, 6 }, 'v', true)
    eq(c.selection_text, 'á🙂'); c:clear()
    c = capture({ 'á🙂z' }, { 1, 6 }, { 1, 0 }, 'v')
    eq(c.selection_text, 'á🙂z'); c:clear(true)
    eq(vim.fn.mode(), 'v'); eq(vim.api.nvim_win_get_cursor(0), { 1, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
    vim.o.tabstop = 4
    c = capture({ '\tab', '123456' }, { 1, 1 }, { 2, 5 }, '\22')
    eq(c.selection_text, 'ab\n56'); c:clear()
    c = capture({ 'one', 'two' }, { 1, 0 }, { 2, 1 }, 'V')
    eq(c.selection_text, 'one\ntwo'); c:clear()
    vim.o.selection = 'inclusive'
  end)

  test('same target deduplicates different cwd and re-reads binding inside lock', function()
    local S = require('opvi.session')
    local release_count, creates, acquire, binding, result = 0, 0, nil, '', {}
    mock('opvi.lock', { acquire = function(_, cb) acquire = cb end, cancel = function() end })
    mock('opvi.tmux', {
      resolve = function(dir, cb) cb({ socket = 'socket', target = 'target', directory = dir }) end,
      ensure = function(_, cb) cb('$10') end,
      binding = function(target, cb) eq(target, '$10'); cb(binding) end,
      bind = function(_, id, cb) binding = id; cb('') end,
    })
    mock('opvi.transport', { request = function(_, path, _, cb)
      if path == '/api/info' then cb({version='2'})
      elseif path == '/api/session' then creates = creates + 1; cb({data={id='ses_new'}})
      else cb({data={id=binding, location={directory='/project'}}}) end
    end })
    S.connect('/project', function(s, e) assert(s,e); table.insert(result,s) end)
    S.connect('/project/child', function(s, e) assert(s,e); table.insert(result,s) end)
    acquire(function() release_count = release_count + 1 end)
    eq(#result,2); eq(creates,1); eq(release_count,1)
    S.connect('/other', function(s) eq(s.id,'ses_external') end)
    binding = 'ses_external' -- Another process bound while we were waiting.
    acquire(function() end)
    eq(creates,1)
  end)

  test('tmux query errors propagate; session lookup is exact', function()
    local T = require('opvi.tmux')
    mock('opvi.process', { run = function(_, _, cb) cb(nil,{code=1,message='no such session'}) end })
    T.binding('$404', function(id, err) eq(id,nil); eq(err,'no such session') end)
    T.ensure({target='target'}, function(id, err) eq(id,nil); eq(err,'no such session') end)
    mock('opvi.process', { run = function(argv, _, cb)
      eq(argv[2],'list-sessions'); cb({stdout='target-extra\t$1\ntarget\t$2'})
    end })
    T.ensure({target='target'}, function(id) eq(id,'$2') end)
  end)

  test('new Ask does not drop pending POST acknowledgement; cancel and rebind never post', function()
    local O = require('opvi')
    local post, posts, input, id = nil, 0, nil, 'ses_test'
    mock('opvi.session', { connect=function(_,cb) cb({id='ses_test',target='$1',cwd='/project'}) end })
    mock('opvi.tmux', { binding=function(_,cb) cb(id) end })
    mock('opvi.ui.ask', { open=function(_,_,cb) input=cb end })
    local tracked = {}
    mock('opvi.status', {track=function(_,_,message) table.insert(tracked,message) end})
    mock('opvi.transport', {request=function(_,path,_,cb) if path:match('/prompt$') then posts=posts+1;post=cb end end})
    O.prompt('A')
    O.ask('B')
    post({data={id='msg_A'}})
    eq(O.last_message_id,'msg_A'); eq(tracked,{'msg_A'})
    input(nil); eq(posts,1)
    O.ask('C'); id='ses_other'; input('C'); eq(posts,1)
  end)

  test('progress ignores old outcome, awaits admission, and catches errors/interruption', function()
    local P = require('opvi.progress')
    eq(P.evaluate({{id='old',type='idle',outcome='succeeded'}},'msg_new').state,'submitted')
    eq(P.evaluate({{id='msg_new',type='user'}},'msg_new').finished,nil)
    local messages = {{id='msg_new',type='user'}, {id='assistant',type='assistant',error={message='Insufficient account funds'}},
      {id='idle',type='idle',outcome='failed'}}
    local result = P.evaluate(messages,'msg_new')
    eq(result.state,'failed'); eq(result.error,'Insufficient account funds'); eq(result.finished,true)
    messages[3].outcome='interrupted'; eq(P.evaluate(messages,'msg_new').state,'interrupted')
    messages[3].outcome='succeeded'; eq(P.evaluate(messages,'msg_new').state,'succeeded')
    mock('opvi.transport', {request=function(_,path,_,cb)
      if path:find('cursor=') then cb({data={messages[1]},cursor={}})
      else cb({data={messages[3],messages[2]},cursor={next='next/page'}}) end
    end})
    P.read('ses_test','msg_new',function(r) eq(r.state,'succeeded') end)
  end)

  test('malformed history retries smaller pages without losing its cursor', function()
    local P=require('opvi.progress')
    local paths,done={},false
    mock('opvi.transport',{request=function(method,path,_,cb)
      eq(method,'get');table.insert(paths,path)
      if #paths==1 then cb({data={{id='idle',type='idle',outcome='succeeded'}},cursor={next='page/2'}})
      elseif #paths<4 then cb(nil,'incomplete response','invalid_json')
      else cb({data={{id='msg_new',type='user'}},cursor={}}) end
    end})
    P.read('ses_test','msg_new',function(r) eq(r.state,'succeeded');done=true end)
    assert(done);eq(#paths,4)
    assert(paths[2]:find('limit=20&cursor=page%2F2',1,true))
    assert(paths[3]:find('limit=10&cursor=page%2F2',1,true))
    assert(paths[4]:find('limit=5&cursor=page%2F2',1,true))
    local calls=0
    mock('opvi.transport',{request=function(_,_,_,cb) calls=calls+1;cb(nil,'broken','invalid_json') end})
    P.read('ses_test','msg_new',function(r,err) eq(r,nil);eq(err,'broken') end)
    eq(calls,5) -- 20, 10, 5, 2, 1; bounded even if a single message is malformed.
    calls=0
    P.read('ses_test','msg_new',function() error('Canceled read called back') end,function() return false end)
    eq(calls,0)
  end)

  test('status tracks multiple messages, preserves extmark anchor, survives transient tmux error', function()
    local S = require('opvi.status')
    require('opvi.config').opts.status.interval=10
    vim.api.nvim_buf_set_lines(0,0,-1,false,{'a','b','c'})
    local context={buf=vim.api.nvim_get_current_buf(),cursor={2,0}}
    local count, finish = 0, false
    mock('opvi.tmux', {binding=function(_,cb)
      count=count+1
      if count==1 then cb(nil,'temporary failure') else cb('ses_test') end
    end})
    mock('opvi.progress', {read=function(_,id,cb)
      cb(finish and {state='succeeded',finished=true} or {state='submitted'})
    end})
    S.track({id='ses_test',target='$1'},context,'msg_one',true)
    S.track({id='ses_test',target='$1'},context,'msg_two',true)
    wait(function() return count>=4 end)
    eq(vim.tbl_count(S.entries),2)
    vim.api.nvim_buf_set_lines(0,0,0,false,{'inserted'})
    local before=count
    wait(function() return count>before+2 end)
    local marks=vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_create_namespace('OpviStatus'),0,-1,{})
    eq(marks[1][2],2); eq(marks[2][2],2)
    finish=true; wait(function() return next(S.entries)==nil end)
    eq(S.results['ses_test:msg_one'].state,'succeeded')
    mock('opvi.progress', {read=function(_,_,cb)
      cb({state='failed',finished=true,error='Upstream request failed: Insufficient account funds'})
    end})
    S.track({id='ses_test',target='$1'},context,'msg_failed',true)
    wait(function() return S.results['ses_test:msg_failed']~=nil end)
    eq(S.results['ses_test:msg_failed'].state,'failed')
    local errors=vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_create_namespace('OpviStatus'),0,-1,{details=true})
    assert(errors[1][4].virt_lines[1][1][1]:find('Insufficient account funds',1,true))
    S.stop()
    eq(#vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_create_namespace('OpviStatus'),0,-1,{}),0)
    local unavailable=true
    mock('opvi.progress',{read=function(_,_,cb)
      if unavailable then cb(nil,'incomplete JSON') else cb({state='running'}) end
    end})
    S.track({id='ses_test',target='$1'},context,'msg_retry',true)
    wait(function() return S.entries['ses_test:msg_retry'].last_error~=nil end)
    local retry_marks=vim.api.nvim_buf_get_extmarks(0,vim.api.nvim_create_namespace('OpviStatus'),0,-1,{details=true})
    eq(retry_marks[1][4].virt_lines[1][1][1],'opvi: status unavailable (retrying)')
    eq(S.results['ses_test:msg_retry'],nil)
    unavailable=false
    wait(function() return S.entries['ses_test:msg_retry'].last_error==nil end)
    S.stop()
  end)

  test('clear status dismisses finished notes without stopping active tracking', function()
    local S = require('opvi.status')
    local ns = vim.api.nvim_create_namespace('OpviStatus')
    local buf = vim.api.nvim_get_current_buf()
    local other = vim.api.nvim_create_buf(false, true)
    local session = {id='ses_clear',target='$1'}
    mock('opvi.tmux', {binding=function(_,cb) cb(session.id) end})
    mock('opvi.progress', {read=function(_,id,cb)
      if id == 'msg_active' then cb({state='running'})
      else cb({state='interrupted',finished=true,error='Step interrupted'}) end
    end})
    S.track(session,{buf=buf,cursor={1,0}},'msg_done',true)
    S.track(session,{buf=other,cursor={1,0}},'msg_other',true)
    S.track(session,{buf=buf,cursor={1,0}},'msg_active',true)
    wait(function() return S.results['ses_clear:msg_done'] and S.results['ses_clear:msg_other'] end)
    vim.cmd('runtime plugin/opvi.lua')
    vim.cmd('OpviClearStatus')
    eq(#vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{}),1)
    eq(#vim.api.nvim_buf_get_extmarks(other,ns,0,-1,{}),1)
    local entry = S.entries['ses_clear:msg_active']
    assert(entry and entry.timer and not entry.timer:is_closing())
    eq(S.results['ses_clear:msg_done'].state,'interrupted')
    vim.cmd('OpviClearStatus!')
    eq(#vim.api.nvim_buf_get_extmarks(other,ns,0,-1,{}),0)
    eq(#vim.api.nvim_buf_get_extmarks(buf,ns,0,-1,{}),1)
    eq(S.entries['ses_clear:msg_active'],entry)
    vim.cmd('OpviClearStatus!')
    S.stop()
    vim.api.nvim_buf_delete(other,{force=true})
  end)

  test('completion and subprocess response contracts', function()
    require('opvi.ui.ask')
    eq(_G.opvi_completion('','explain @buff'),{'explain @buffer','explain @buffers'})
    vim.api.nvim_buf_set_lines(0,0,-1,false,{'á @buf'})
    vim.api.nvim_buf_set_name(0,'/tmp/opencode/opvi-completion-'..vim.fn.getpid())
    local provider=require('opvi.ui.cmp').cmd()
    local completed
    provider.request('textDocument/completion',{
      textDocument={uri=vim.uri_from_bufnr(vim.api.nvim_get_current_buf())},position={line=0,character=6},
    },function(_,items) completed=items end)
    eq(completed[1].textEdit.range.start.character,2)
    local T=require('opvi.transport')
    local done
    require('opvi.config').opts.api.command={'sh','-c','printf ""'}
    T.request('post','/model',{},function(body,err) eq(err,nil);eq(body,{});done=true end)
    wait(function() return done end)
    done=false
    require('opvi.config').opts.api.command={'sh','-c','printf nope'}
    T.request('get','/info',nil,function(body,err) eq(body,nil);assert(err);done=true end)
    wait(function() return done end)
    require('opvi.config').opts.api.command=nil
  end)
  test('large CLI output drains fully, including Unicode and final JSON fields', function()
    local T=require('opvi.transport')
    local done
    require('opvi.config').opts.api.command={'python3',vim.fn.getcwd()..'/tests/large_response.py'}
    T.request('get','/api/session/ses_test/message?limit=1',nil,function(body,err)
      assert(body,err);eq(body.data.complete,true);eq(body.data.text,string.rep('á🙂',100000));done=true
    end)
    wait(function() return done end)
    require('opvi.config').opts.api.command=nil
  end)
  test('buffered CLI timeout terminates the child command', function()
    local path='/tmp/opencode/opvi-child-'..vim.fn.getpid()
    local config=require('opvi.config').opts.api
    local timeout=config.timeout
    config.timeout=500
    config.command={'python3','-c', 'import os,time;open('..string.format('%q',path)..',"w").write(str(os.getpid()));time.sleep(60)'}
    local done
    require('opvi.transport').request('get','/info',nil,function(body,err) eq(body,nil);assert(err);done=true end)
    wait(function() return done end)
    local pid=tonumber(vim.fn.readfile(path)[1])
    local alive=vim.uv.kill(pid,0)
    assert(not alive,'CLI child survived timeout')
    vim.fn.delete(path)
    config.command,config.timeout=nil,timeout
  end)
  test('lock helper releases on stdin close', function()
    local L=require('opvi.lock')
    local first, second
    L.acquire('test-'..vim.fn.getpid(),function(release,err) assert(release,err);first=release end)
    wait(function() return first~=nil end)
    L.acquire('test-'..vim.fn.getpid(),function(release,err) assert(release,err);second=release end)
    vim.wait(100,function() return second~=nil end)
    eq(second,nil);first();wait(function() return second~=nil end);second()
  end)
  test('disconnect cancels queued lock callbacks and releases lock', function()
    local L=require('opvi.lock')
    local first, second, canceled
    local key='cancel-test-'..vim.fn.getpid()
    L.acquire(key,function(release,err) assert(release,err);first=release end)
    wait(function() return first~=nil end)
    L.acquire(key,function() canceled=true end)
    L.cancel()
    L.acquire(key,function(release,err) assert(release,err);second=release end)
    wait(function() return second~=nil end);eq(canceled,nil);second()
  end)
  test('statusline component follows connection state and session title', function()
    local state,lualine=require('opvi.state'),require('opvi.lualine')
    local events={}
    local group=vim.api.nvim_create_augroup('OpviStateTest',{clear=true})
    vim.api.nvim_create_autocmd('User',{group=group,pattern='OpviStateChanged',
      callback=function(e) table.insert(events,e.data) end})
    state.clear()
    eq(lualine.render(),'󱚧')
    eq(state.set('connecting'),true)
    eq(state.set('connecting'),false,'unchanged state must not redraw')
    eq(events[#events].phase,'connecting')
    state.set('connected',{id='ses_abc'},'  Fix   the\nlualine icon ')
    eq(state.title,'Fix the lualine icon')
    eq(lualine.render(),'󰚩 Fix the lualine icon')
    eq(lualine.color().fg,'#585858')
    state.set('connected',{id='ses_abc'})
    eq(lualine.render(),'󰚩 ses_abc','falls back to the session ID before a title exists')
    state.set('error',nil,nil,'stale binding')
    eq(lualine.render(),'󱚧')
    lualine.setup({connected='C',idle='I',fg='#999999',max_width=20})
    state.set('connected',{id='ses_abc'},'A very long session title that must be cut')
    eq(lualine.render(),'C A very long sessi...')
    eq(#lualine.render(),22)
    lualine.setup({max_width=0})
    eq(lualine.render(),'C A very long session title that must be cut')
    lualine.setup({max_width=40})
    state.set('connected',{id='ses_abc'},'Real title')
    mock('opvi.transport',{request=function(_,path,_,cb) eq(path,'/api/session/ses_abc');cb({data={id='ses_abc',title='Real title'}}) end})
    state.refresh_title()
    eq(lualine.render(),'C Real title')
    state.set('connected',{id='ses_abc'})
    mock('opvi.transport',{request=function(_,_,_,cb) cb({data={id='ses_other',title='Stale'}}) end})
    state.refresh_title()
    eq(lualine.render(),'C ses_abc','ignores a response for a different session')
    state.clear()
    eq(lualine.render(),'I')
    lualine.setup({connected='󰚩',idle='󱚧',fg='#585858',max_width=40})
    vim.api.nvim_del_augroup_by_id(group)
  end)
  test('live tests fail closed on model-switch error, mismatch, or paid model', function()
    local H=dofile('tests/live_helpers.lua')
    local step, behavior=0,'error'
    H.request=function(method,path)
      step=step+1
      if path=='/api/model' then
        return {data={{id='free',providerID='test',cost={{input=behavior=='paid' and 1 or 0,output=0,cache={read=0,write=0}}}}}}
      end
      if method=='post' then
        if behavior=='error' then error('switch failed') end
        return {}
      end
      return {data={model={id=behavior=='mismatch' and 'paid' or 'free',providerID='test'}}}
    end
    assert(not pcall(H.pin_free_model,'ses_test','test/free'));eq(step,2)
    behavior,step='mismatch',0
    assert(not pcall(H.pin_free_model,'ses_test','test/free'));eq(step,3)
    behavior,step='paid',0
    assert(not pcall(H.pin_free_model,'ses_test','test/free'));eq(step,1)
    behavior,step='success',0
    H.pin_free_model('ses_test','test/free');eq(step,3)
  end)
  print(passed .. ' regression groups passed')
end
local ok, err = xpcall(main, debug.traceback)
restore()
require('opvi.status').stop()
require('opvi.process').cancel()
require('opvi.lock').cancel()
if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') else vim.cmd('qa!') end
