let s:javac_core_command = 'javac -cp .cache/*:target/classes -g:lines,vars,source -sourcepath src/main/java -d target/classes'
let s:javac_test_command = 'javac -cp .cache/*:target/classes:target/test-classes -g:lines,vars,source -sourcepath src/main/java:src/test/java -d target/test-classes'
let s:junit_exec = 'java -cp .cache/*:target/classes:target/test-classes org.junit.runner.JUnitCore'
let s:javap_exec = 'javap -public -classpath .cache/*:target/classes:target/test-classes'
let s:javap_curr_exec = 'javap -private -classpath .cache/*:target/classes:target/test-classes'
let b:compile_on_save = 0
let s:autocompl_inserted = 0
let s:selected_class = ''
let g:dict_javavim = {}
"code taken from xptemplate plugin
let s:let_sid = 'map <Plug>jsid <SID>|let s:sid=matchstr(maparg("<Plug>jsid"), "\\d\\+_")|unmap <Plug>jsid'
exe s:let_sid

let s:method_def_expr =
\ '\v^%(\t|    )%((private |protected |public )%((public|private|protected)@!))?[[:alnum:]]+(\<.+\>)?[[:space:]\n]{1,}[[:alnum:]\$]+\s{-}\('
let s:method_bodystart_expr = '\v\{'

fun! CacheThisMavenProj() abort "{{{
  let adir = matchstr(findfile('pom.xml', '.;'), '\v.+\zepom\.xml$')
  if adir == '' | let adir = './' | endif
  let cmd_height = &cmdheight
  set cmdheight=3
  let is_regenerated = s:prompt_regenerate_cache(adir)
  exe "set cmdheight=" . cmd_height
  if is_regenerated
    call s:populate_cache(adir)
  endif
endfunction "}}}

fun! s:prompt_regenerate_cache(adir) "{{{
  let adir = a:adir . '.cache'
  let regenerated=1
  if isdirectory(adir)
    echo 'Do you want to regenerate cache?'
    echo '================================'
    echo 'y/n '
    let response = nr2char(getchar())
    if response =~? 'y'
      call s:delete_dir(adir)
    else
      redraw | echo "Cache preserved"
      let regenerated = 0
    endif
  endif
  return regenerated
endfunction "}}}

fun! s:delete_dir(a_dir) "{{{
  if has('win32')
    call system('rd /q /s ' . a:a_dir)
  else
    call system('rm -rf ' . a:a_dir)
  endif
endfunction "}}}

fun! s:populate_cache(a_dir) abort "{{{
  call mkdir(a:a_dir . '.cache', 'p')
  let cwd_ = getcwd()
  exe "cd " . a:a_dir
  let paths = s:parse_mvn_output()
  call s:copy_files_to_cache(paths)
  exe "cd " . cwd_
endfunction "}}}

fun! s:parse_mvn_output() "{{{
  let mvn_output = system('mvn dependency:build-classpath')
  let lines = split(mvn_output, '\n')
  let line = filter(lines, 'v:val =~ ''\vjar[;:]'' && v:val !~ ''\vWARNING''')[0]
  let paths = split(line, '\v(^C|;C)@<![:;]')
  return paths
endfunction "}}}

fun! s:copy_files_to_cache(files) "{{{
  if has('win32')
    call s:exec_copies_win32(a:files)
  else
    call s:exec_copies(a:files)
  endif
endfunction "}}}

fun! s:exec_copies_win32(files) "{{{
  let len_of_files = len(a:files)
  let files_to_copy = []
  let partial_lists = s:create_sublists(a:files, 25)
  let counter = 0
  for files_to_copy in partial_lists
    call s:exec_copy_command_win32(files_to_copy)
    let counter += len(files_to_copy)
    redraw | echo counter . ' / ' . len_of_files
  endfor
  redraw | echo 'DONE creating jar cache'
endfunction "}}}

fun! s:get_method_def() dict "{{{
  let method_start_line = search(s:method_def_expr, 'bcn')
  let lines_of_method_def = [getline(method_start_line)]
  let line_counter = method_start_line + 1
  while (getline(line_counter-1) !~ s:method_bodystart_expr)
    call add(lines_of_method_def, getline(line_counter))
    let line_counter+=1
  endwhile
  let self.definition = substitute(join(lines_of_method_def, ' '), '\v\s{2,}', ' ', 'g')
  let self.definition = substitute(self.definition, '\v^\s+', '', '')
  return self.definition
endfunction "}}}

fun! s:strip_parens() dict "{{{
  let self.definition = substitute(substitute(self.definition, '\v.*\(\s*', '', ''),
    \ '\v\s*\).*', '', '')
  return self.definition
endfunction "}}}

fun! s:strip_generics() dict "{{{
  let self.definition = substitute(self.definition, '\v\<.+\>', '', 'g')
  return self.definition
endfunction "}}}

fun! s:return_def_variables() dict "{{{
  call self.methoddef()
  call self.strip_parens()
  call self.strip_generics()
  return split(self.definition, '\s*,\s*')
endfunction "}}}

fun! s:exec_copies(files) "{{{
  let files = map(copy(a:files), 'fnameescape(v:val)')
  let cmdstr = 'cp ' . join(files, ' ') . ' .cache'
  call system(cmdstr)
  redraw | echo 'DONE creating jar cache'
endfunction "}}}

fun! s:exec_copy_command_win32(files) "{{{
  let cmdstr = ''
  for path in a:files
    let cmdstr .= 'copy ' . fnameescape(path) . ' .cache && '
  endfor
  let cmdstr = substitute(cmdstr, '\v&&\s*$', '', '') . ' .cache'
  call system(cmdstr)
endfunction "}}}

fun! s:create_sublists(files, size) "{{{
  let partial_lists = []
  let local_files = copy(a:files)
  while len(local_files) > 0
    let list_size = len(local_files)
    let mod_ = len(local_files) % a:size
    if mod_ > 0
      let foo = remove(local_files, -1 * mod_, -1)
      call add(partial_lists, foo)
    else
      let foo = remove(local_files, -1 * a:size, -1)
      call add(partial_lists, foo)
    endif
  endwhile
  return partial_lists
endfunction "}}}

fun! s:list_classes_win32(file_sublists, total) "{{{
  let counter = 0
  for sublist in a:file_sublists
    call map(sublist, 's:str_jartf_call(v:val, ''findstr'')')
    " && echo on <-- it's added because system(...) ignores last command
    " after "&&" I don't know why
    let command = join(sublist, ' && ') . ' && echo on'
    call system(command)
    let counter += len(sublist)
    redraw | echom counter ' / ' . a:total
  endfor
  redraw | echom 'DONE listing classes'
endfunction "}}}

fun! s:list_classes(file_sublists, total) "{{{
  let counter = 0
  for sublist in a:file_sublists
    call map(sublist, 's:str_jartf_call(v:val, ''grep'')')
    let command = join(sublist, ' && ')
    call system(command)
    let counter += len(sublist)
    redraw | echom counter ' / ' . a:total
  endfor
endfunction "}}}

fun! s:str_jartf_call(file_name, grep_expr) "{{{
  return substitute(substitute(a:file_name, '\v^', 'jar tf ', ''),
        \ '\v$', ' | ' . a:grep_expr . ' class$ >> classes.index', '')
endfunction "}}}

fun! s:sort_file_index() "{{{
  let lines = []
  if filereadable('classes.index')
    let lines = readfile('classes.index')
    call filter(lines, 'v:val =~ ''\v^[^$]+$'' && v:val !~ ''package-info''')
    call map(lines, 's:reformat_index_line(v:val)')
    call sort(lines)
    call writefile(lines, 'classes.index')
  endif
endfunction "}}}

fun! s:reformat_index_line(index_line) "{{{
  return substitute(substitute(a:index_line, '\v^(.+/(\w+)).class', '\2	\1', ''),
    \ '\v/', '.', 'g')
endfunction "}}}

fun! s:extract_class_names() "{{{
  let lines = readfile('classes.index')
  let classnames = map(copy(lines), 'matchstr(v:val, ''\v^\S+\ze	.*'')')
  let classnames = filter(copy(classnames), 'index(classnames, v:val, v:key+1) == -1')
  call writefile(classnames, 'classnames.index')
endfunction "}}}

fun! s:sort_file_index_cd() "{{{
  let dirs = s:calculate_dirs()
  exe 'lcd ' . dirs.project_dir
  lcd .cache
  call s:extract_class_names()
  exe 'lcd ' . dirs.cwd_
endfunction "}}}

command! FileIndexSort call s:sort_file_index_cd()

fun! List_classes_cache() "{{{
  let dirs = s:calculate_dirs()
  exe "lcd " . dirs.project_dir
  lcd .cache
  try
    let jar_files = split(globpath('.', "*.jar"), '\n')
    let sublists = s:create_sublists(jar_files, 15)
    if has('win32')
      call s:list_classes_win32(sublists, len(jar_files))
    else
      call s:list_classes(sublists, len(jar_files))
    endif
    call s:sort_file_index()
  finally
    exe "lcd " . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:calculate_dirs() "{{{
  let project_dir = fnameescape(matchstr(findfile('pom.xml', '.;'), '\v.+\zepom\.xml$'))
  if project_dir == ''
    let project_dir = '.'
  endif
  let cwd_dir = fnameescape(getcwd())
  return {'project_dir': project_dir, 'cwd_dir': cwd_dir}
endfunction "}}}

fun! s:createclassesdirs() "{{{
  if !isdirectory('target/classes')
    call mkdir('target/classes', 'p')
  endif
  if !isdirectory('target/test-classes')
    call mkdir('target/test-classes', 'p')
  endif
endfunction "}}}

fun! JavaCBuffer() "{{{
  let dirs = s:calculate_dirs()
  let javac = s:javac_core_command
  if expand('%:t') =~ '\vTest|It'
    let javac = s:javac_test_command
  endif
  try
    execute 'lcd ' . dirs.project_dir
    call s:createclassesdirs()
    let output = system(s:normalize_command(javac . ' ' . expand('%')))
    redraw
    if output == ''
      echom 'OK'
    else
      let lines = split(output, '\v\n')
      for l in lines | echom l | endfor
    endif
  catch /.*/
  finally
    execute 'lcd ' . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:normalize_command(command) "{{{
  if has('win32')
    return substitute(a:command, '\v(-g|C)@<!:', ';', 'g')
  endif
endfunction "}}}

let b:is_compile_on_save = 0
fun! ToggleSettingCompileOnSave() "{{{
  let b:is_compile_on_save = !b:is_compile_on_save
endfunction "}}}

fun! CompileOnSave() "{{{
  if &ft == 'java' && b:is_compile_on_save
    JavaC
  endif
endfunction "}}}

fun! JUnitCurrent() abort "{{{
  let dirs = s:calculate_dirs()
  exe 'lcd ' . dirs.project_dir
  let class_name = s:current_clazz()
  try
    let output = system(s:normalize_command(s:junit_exec . ' ' . class_name))
    let lines = split(output, '\v\n')
    for l in lines | echom l | endfor
  finally
    exe 'lcd ' . dirs.cwd_dir
  endtry
endfunction "}}}

fun! JavapVar_Annotation()
  let desc = s:descVar_Annotation()
endfunction "}}}

fun! s:descVar_annotation() "{{{
  let desc = {}
  let var_annotation = expand('<cWORD>')
  if var_annotation =~? '\v<\@'
    let desc.type = 'annotation'
  endif

  if expand('<cword>') =~# '\v\C[a-z]'
    let desc.type = 'variable'
  elseif expand('<cword>') =~# '\v\C[A-z]'
    let desc.type = 'class'
  endif
  if desc.type == 'annotation'
    let search_for_import = expand('<cword>')
  endif
  return desc
endfunction "}}}

fun! s:exec_javap(clazz) "{{{
  return split(system(s:normalize_command(s:javap_exec . ' ' . a:clazz)), '\n')
endfunction "}}}

fun! s:javap_current() "{{{
  let dirs = s:calculate_dirs()
  exe 'lcd ' . dirs.project_dir
  try
    let lines = split(system(s:normalize_command(s:javap_curr_exec. ' '
          \ . s:current_clazz())), '\n')
    for l in lines | echom l | endfor
  finally
    exe 'lcd ' . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:current_clazz() "{{{
  let clazz = expand('%')
  let clazz = substitute(clazz, '\v\.java$', '', '')
  let clazz = substitute(clazz, '\vsrc[\\/](main|test)[\\/]java[\\/]', '', '')
  let clazz = substitute(clazz, '\v[\\/]', '.', 'g')
  return clazz
endfunction "}}}

"this function is called when current word is not property of the
"class loaded in the current buffer. And when it's not an annotation
"Not a constant and is not in the parameters of the method
fun! FindDeclaredType() abort "{{{
"s:method_def_expr <-- is The madness of a expression Which finds line where method begins
" I normally format files so, this has to match almost always -> '\v^%(\t|    )\}'
  let word = expand('<cword>')
  let stopline = searchpair(
        \ s:method_def_expr 
        \ , ''
        \ , '\v^%(\t|    )}'
        \ , 'bn')
  let search_expr = '\v^\s+(final\s)?\S+.*(\=)@<!\s<' . word . '>\s*[;=].*$'
  let def_line = search(search_expr, 'cbnW', stopline)
  return substitute(
        \ substitute(
        \ substitute(getline(def_line),'\v^\s+(final\s)?\S+.{-}\zs<' . word . '>.*','', '')
        \ , '\v\<[^>]\>', '', '')
        \ , '\v^\s+|\s+$', '', 'g')
endfunction "}}}

fun! s:findDeclaredTypeInMethod() "{{{
  let variables = g:dict_javavim.def_variables_method()
  let variableNames = map(copy(variables), 'matchstr(v:val, ''\v\w+$'')')
  let position = index(variableNames, expand('<cword>'))
  if position >= 0
    return matchstr(variables[position], '\v^\w+')
  else
    return ''
  endif
endfunction "}}}

fun! Javapcword() "{{{
  let word = expand('<cword>')
  if getline(line('.'))[col('.') - 1] !~ '\w'
    echohl WarningMsg | echom 'NOT ON <cword>' | echohl None
    return
  endif
  let dirs = s:calculate_dirs()
  try
    exe "lcd " . dirs.project_dir
    let type = s:findDeclaredTypeInMethod()
    if type == ''
      let type = FindDeclaredType()
    endif
    let line_import = FindImport(type)
    let clazz = matchstr(getline(line_import), '\v^import\s+\zs.*\ze\W')
    let lines = split(system(s:normalize_command(s:javap_exec . ' ' . clazz)), '\v\n')
    for l in lines | echom l | endfor
  finally
    exe "lcd " . dirs.cwd_dir
  endtry
endfunction "}}}

fun! FindImport(clazz) "{{{
  let a_class = a:clazz
  let expression = '^import .\+\<' . a_class . ';'

  let _pos = searchpos(expression, 'bn')[0]

  if _pos == 0
    throw 'Type could not be determined'
  endif

  return _pos
endfunction "}}}

fun! CreateAutoImportWindow(back_to_insert_mode) "{{{
  let working_window = bufwinnr('%')
  let dirs = s:calculate_dirs()
  exe 'lcd ' . dirs.project_dir
  try
    let search_term = expand('<cword>')
    keepalt bot new
    silent f auto import list
    setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile number
    setlocal nonu
    call s:fill_buffer_imports(search_term)
    setl nomodifiable
    call s:mappings_for_auto_import_window(a:back_to_insert_mode)
  finally
    exe "lcd " . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:fill_buffer_imports(search_term) "{{{
  let lines_imports = s:grep_cword_from_index(a:search_term)
  call setline(1, lines_imports[0])
  if len(lines_imports) > 0
    call append(1, lines_imports[1:])
  endif
endfunction "}}}

fun! s:grep_cword_from_index(search_term) "{{{
    if has('win32')
      let search_expr = 'findstr /I "^' . a:search_term . '" < ' . '.cache/classes.index'
    else
      let search_expr = 'grep -i -e ^' . a:search_term . ' .cache/classes.index'
    endif
    let contents = split(system(search_expr), '\n')
    return contents
endfunction "}}}

fun! s:mappings_for_auto_import_window(back_to_insert_mode) "{{{
  let s:back_to_insert_mode = a:back_to_insert_mode
  nnoremap <silent><buffer> q ZZ
  nnoremap <silent><buffer> u <Nop>
  nnoremap <silent><buffer> p <Nop>
  nnoremap <silent><buffer> P <Nop>
  nnoremap <silent><buffer> o <Nop>
  nnoremap <silent><buffer> O <Nop>
  nnoremap <silent><buffer> a <Nop>
  nnoremap <silent><buffer> A <Nop>
  nnoremap <silent><buffer> i <Nop>
  nnoremap <silent><buffer> I <Nop>
  nnoremap <silent><buffer> <C-w>h <Nop>
  nnoremap <silent><buffer> <C-w>j <Nop>
  nnoremap <silent><buffer> <C-w>k <Nop>
  nnoremap <silent><buffer> <C-w>l <Nop>
  nnoremap <silent><buffer> <C-w>w <Nop>
  nnoremap <silent><buffer> <C-w>p <Nop>
  nnoremap <silent><buffer> <Tab>  :<C-U>call <SID>move_down(v:count1)<CR>
  nnoremap <silent><buffer> <BS>   :<C-U>call <SID>move_up(v:count1)<CR>
  exe "nnoremap \<silent>\<buffer> \<CR> :call \<SID>import_current_class( ". s:back_to_insert_mode . " )\<CR>"
endfunction "}}}

fun! s:import_current_class(back_to_insert_mode) "{{{
  let import = matchstr(getline(line('.')), '\v^[^	]+	\zs.*')
  let import = 'import ' . import . ';'
  normal q
  let already_imported = search('\v^import' . import, 'bnW')
  if already_imported
    echohl WarningMsg | echom 'Already Imported' | echohl None
  else
    let last_import = search('\v^import\s(static)@!.*$', 'bnW')
    call append(last_import, import)
  endif
  if a:back_to_insert_mode
    call feedkeys("a\<C-x>\<C-n>")
  endif
endfunction "}}}

fun! s:move_up(count) "{{{
  if line('.') - a:count <= 0
    let additional_move = a:count - line('.')
    normal G
    if additional_move > 0
      exe 'normal ' . additional_move . 'k'
    endif
    return
  endif
  exe 'normal ' . a:count . 'k'
endfunction "}}}

fun! s:move_down(count) "{{{
  if line('.') + a:count > line('$')
    let additional_move = line('.') + a:count - (line('$') + 1)
    normal gg
    if additional_move > 0
      exe 'normal ' . additional_move . 'j'
    endif
    return
  endif
  exe 'normal ' . a:count . 'j'
endfunction "}}}

augroup command_on_save
  au!
  au BufWritePost *.java call CompileOnSave()
augroup END

let g:dict_javavim['methoddef'] = function('<SNR>' . s:sid . 'get_method_def')
let g:dict_javavim['strip_parens'] = function('<SNR>' . s:sid . 'strip_parens')
let g:dict_javavim['strip_generics'] = function('<SNR>' . s:sid . 'strip_generics')
let g:dict_javavim['def_variables_method'] = function('<SNR>' . s:sid . 'return_def_variables')

command! -buffer CompileOnSaveToggle call ToggleSettingCompileOnSave()
command! -buffer CacheCurrProjMaven call CacheThisMavenProj()
command! -buffer JavaC call JavaCBuffer()
command! -buffer Junit call JUnitCurrent()
command! -buffer Javap call Javapcword()
nnoremap <silent><buffer> g7 :call <SID>javap_current()<cr>
inoremap <silent><buffer> <C-g><C-p> <Esc>:call CreateAutoImportWindow(1)<cr>
inoremap <silent><buffer> <C-g>p <Esc>:call CreateAutoImportWindow(1)<cr>
nnoremap <silent><buffer> <C-g><C-p> :call CreateAutoImportWindow(0)<cr>
nnoremap <silent><buffer> <C-g>p :call CreateAutoImportWindow(0)<cr>

