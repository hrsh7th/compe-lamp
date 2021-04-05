let s:Position = vital#lamp#import('VS.LSP.Position')
let s:MarkupContent = vital#lamp#import('VS.LSP.MarkupContent')

let s:state = {
\   'source_ids': [],
\   'cancellation_token': lamp#cancellation_token(),
\ }

"
" compe_lamp#source#attach
"
function! compe_lamp#source#attach() abort
  augroup compe_lamp#source#attach
    autocmd!
    autocmd User lamp#server#initialized call s:source()
    autocmd User lamp#server#exited call s:source()
  augroup END
  call s:source()
endfunction

"
" source
"
function! s:source() abort
  for l:source_id in s:state.source_ids
    call compe#unregister_source(l:source_id)
  endfor
  let s:state.source_ids = []

  let l:servers = lamp#server#registry#all()
  let l:servers = filter(l:servers, { _, server -> server.supports('capabilities.completionProvider') })
  let s:state.source_ids = map(copy(l:servers), { _, server ->
  \   compe#register_source('lamp', {
  \     'metadata': function('s:metadata', [server]),
  \     'determine': function('s:determine', [server]),
  \     'resolve': function('s:resolve', [server]),
  \     'execute': function('s:execute', [server]),
  \     'complete': function('s:complete', [server]),
  \   })
  \ })
endfunction

"
" metadata
"
function! s:metadata(server) abort
  return {
  \   'priority': 1000,
  \   'menu': '[LSP]',
  \   'filetypes': a:server.filetypes
  \ }
endfunction

"
" s:determine
"
function! s:determine(server, context) abort
  if index(a:server.filetypes, a:context.filetype) == -1
    return {}
  endif

  return compe#helper#determine(a:context, {
  \   'trigger_characters': a:server.capabilities.get_completion_trigger_characters()
  \ })
endfunction

"
" resolve
"
function! s:resolve(server, args) abort
  if !a:server.supports('capabilities.completionProvider.resolveProvider')
    return a:args.callback(a:args.completion_item)
  endif
  let l:p = a:server.request('completionItem/resolve', a:args.completion_item)
  let l:p = l:p.then({ resolved_completion_item -> s:on_resolve(a:args, resolved_completion_item) })
  let l:p = l:p.catch({ -> s:on_resolve(a:args, a:args.completion_item) })
endfunction
function! s:on_resolve(args, completion_item) abort
  call a:args.callback(a:completion_item)
endfunction

"
" execute
"
function! s:execute(server, args) abort
  let l:completion_item = a:args.completion_item
  echomsg string(l:completion_item)
endfunction

"
" complete
"
function! s:complete(server, args) abort
  call s:state.cancellation_token.cancel()
  let s:state.cancellation_token = lamp#cancellation_token()

  let l:request = {}
  let l:request.textDocument = lamp#protocol#document#identifier(bufnr('%'))
  let l:request.position = s:Position.cursor()
  let l:request.context = {}
  let l:request.context.triggerKind = a:args.trigger_character_offset > 0 ? 2 : (a:args.incomplete ? 3 : 1)
  if a:args.trigger_character_offset > 0
    let l:request.context.triggerCharacter = a:args.context.before_char
  endif

  let l:p = a:server.request('textDocument/completion', l:request, {
  \   'cancellation_token': s:state.cancellation_token,
  \ })
  let l:p = l:p.catch({ -> a:args.abort() })
  let l:p = l:p.then({ response -> s:on_complete(a:server, a:args, l:request, response) })
endfunction
function! s:on_complete(server, args, request, response) abort
  if a:response is# v:null
    return a:args.abort()
  endif

  call a:args.callback(a:response)
endfunction


