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
  \     'get_metadata': function('s:get_metadata', [server]),
  \     'determine': function('s:determine', [server]),
  \     'resolve': function('s:resolve', [server]),
  \     'documentation': function('s:documentation', [server]),
  \     'confirm': function('s:confirm', [server]),
  \     'complete': function('s:complete', [server]),
  \   })
  \ })
endfunction

"
" s:get_metadata
"
function! s:get_metadata(server) abort
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
  let l:completion_item = a:args.completed_item.user_data.compe.completion_item
  if a:server.supports('capabilities.completionProvider.resolveProvider')
    let l:ctx = {}
    function! l:ctx.callback(args, completion_item) abort
      let a:args.completed_item.user_data.compe.completion_item = a:completion_item
      call a:args.callback(a:args.completed_item)
    endfunction
    call a:server.request('completionItem/resolve', l:completion_item).then({
    \   completion_item -> l:ctx.callback(a:args, completion_item)
    \ }).catch({ ->
    \   l:ctx.callback(a:args, l:completion_item)
    \ })
  else
    call a:args.callback(a:args.completed_item)
  endif
endfunction

"
" documentation
"
function! s:documentation(server, args) abort
  let l:completion_item = a:args.completed_item.user_data.compe.completion_item
  let l:document = []
  if has_key(l:completion_item, 'detail')
    let l:document += [printf('```%s', a:args.context.filetype)]
    let l:document += [l:completion_item.detail]
    let l:document += ['```']
  endif
  if has_key(l:completion_item, 'documentation')
    if has_key(l:completion_item, 'detail')
      let l:document += ['']
    endif
    let l:document += [s:MarkupContent.normalize(l:completion_item.documentation)]
  endif
  call a:args.callback(l:document)
endfunction

"
" confirm
"
function! s:confirm(server, args) abort
  call compe#confirmation#lsp({
  \   'completed_item': a:args.completed_item,
  \   'completion_item': a:args.completed_item.user_data.compe.completion_item,
  \   'request_position': a:args.completed_item.user_data.compe.request_position,
  \ })
endfunction

"
" complete
"
let s:id = 0
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

  let s:id += 1
  " echomsg string('request' . s:id . ': ' . a:args.context.before_line)
  let l:p = a:server.request('textDocument/completion', l:request, {
  \   'cancellation_token': s:state.cancellation_token,
  \ })
  let l:p = l:p.catch({ -> a:args.abort() })
  let l:p = l:p.then({ response ->
  \   s:on_response(
  \     a:server,
  \     a:args,
  \     l:request,
  \     response
  \   )
  \ })
endfunction
"
" on_response
"
function! s:on_response(server, args, request, response) abort
  if a:response is# v:null
    return a:args.abort()
  endif

  call a:args.callback(a:response)
endfunction


