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

let s:completion_dict = {}

let s:method_def_expr =
\ '\v^%(\t|    )%((private |protected |public )%((public|private|protected)@!))?[[:alnum:]]+(\<.+\>)?[[:space:]\n]{1,}[[:alnum:]\$_]+\s{-}\('
let s:method_bodystart_expr = '\v\{'

fun! CacheThisMavenProj() abort "{{{
  let adir = fnamemodify(findfile('pom.xml', '.;'), ':h')
  if adir =~ '\v^$' | let adir = '.' | endif
  if adir !~ '\v/$' | let adir .= '/' | endif
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
  let l:dir = s:normalize_command(a:a_dir)
  if has('win32')
    call system('rd /q /s ' . l:dir)
  else
    call system('rm -rf ' . l:dir)
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
  let self.definition = matchstr(self.definition, '(\zs.*\ze)')
  return self.definition
endfunction "}}}

fun! s:strip_to_plain_params() dict "{{{
  let l:definition = substitute(self.definition, '\v\s*\@\w+(\(.{-}\))?\s*', '', 'g')
  let self.definition = substitute(l:definition, '\v\<.+\>', '', 'g')
  return self.definition
endfunction "}}}

fun! s:return_def_variables() dict "{{{
  call self.methoddef()
  call self.strip_parens()
  call self.strip_to_plain_params()
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
  exe 'lcd ' . dirs.cwd_dir
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
    return substitute(substitute(a:command, '\v(-g|C)@<!:', ';', 'g')
          \ , '\v/', '\\', 'g')
  endif
  return a:command
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

fun! s:exec_javap(clazz, full) "{{{
  let l:cmd = s:javap_exec
  if a:full
    let l:cmd = s:javap_curr_exec
  endif
  let l:output = system(s:normalize_command(l:cmd . ' ' . a:clazz))
  return split(l:output, '\n')
endfunction "}}}

fun! s:javap_current() "{{{
  let dirs = s:calculate_dirs()
  exe 'lcd ' . dirs.project_dir
  try
    let lines = s:exec_javap(s:current_clazz(), 1)
    for l in lines | echom l | endfor
  finally
    exe 'lcd ' . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:examine_javap_current() "{{{
  let dirs = s:calculate_dirs()
  exe 'lcd ' . dirs.project_dir
  try
    return exec_javap(s:current_clazz(), 1)
  finally
    exe 'lcd ' . dirs.cwd_dir
  endtry
endfunction "}}}

"This method only works when vim is already in project's root dir
fun! s:current_clazz() "{{{
  let clazz = expand('%')
  let clazz = substitute(clazz, '\v\.java$', '', '')
  let clazz = substitute(clazz, '\vsrc[\\/](main|test)[\\/]java[\\/]', '', '')
  let clazz = substitute(clazz, '\v[\\/]', '.', 'g')
  return clazz
endfunction "}}}

"this function is called when current word is not property of the
"class loaded in the current buffer and when is not in the parameters of the
"method
fun! FindDeclaredType(variable) abort "{{{
"s:method_def_expr <-- is The madness of a expression Which finds line where
"method begins I normally keep files well indented so, '\v^%(\t|    )\}' will
"match correctly almost always
  let stopline = searchpair(
        \ s:method_def_expr 
        \ , ''
        \ , '\v^%(\t|    )}'
        \ , 'bn')
  let search_expr = '\v^\s+(final\s)?\S+.*(\=)@<!\s' . a:variable . '\s*[;=].*$'
  let def_line = search(search_expr, 'cbnW', stopline)

  return substitute(
        \ substitute(
        \ matchstr(getline(def_line),'\v^\s+(final\s)?\S+.{-}\ze\s' . a:variable . '.*')
        \ , '\v\<[^>]\>', '', '')
        \ , '\v^\s+|\s+$', '', 'g')
endfunction "}}}

fun! s:findDeclaredTypeInMethod(variable) "{{{
  let variables = g:dict_javavim.def_variables_method()
  let variableNames = map(copy(variables), 'matchstr(v:val, ''\v\w+$'')')
  let position = index(variableNames, a:variable)
  if position >= 0
    return matchstr(variables[position], '\v^\w+')
  else
    return ''
  endif
endfunction "}}}

fun! s:findDeclaredTypeInJavapOutput(var) abort "{{{
  let javap_output = s:exec_javap(s:current_clazz(), 1)
  let vars = filter(copy(javap_output), 'v:val =~ ''\v' . a:var . ';$''')
  call map(vars, 'matchstr(v:val, ''\v^.+\.\zs\S+\ze\s+[\$_[:alnum:]]+;$'')')
  if empty(vars)
    return ''
  else
    return vars[0]
  endif
endfunction "}}}

" This method was sort of a spike and would be deleted
fun! Javapcword() "{{{
  let cur_line = getline(line('.'))
  let cur_col = col('.')
  if cur_line[cur_col - 1] !~ '\w' "Not on cword
    echohl WarningMsg | echom 'NOT ON <cword>' | echohl None
  endif
  let word = expand('<cword>')
  let word = substitute(word, '\v\$', '\\$', 'g')

  let dirs = s:calculate_dirs()
  try
    exe "lcd " . dirs.project_dir
    let type = s:findDeclaredTypeInMethod(word)
    if type == ''
      let type = s:findDeclaredTypeInJavapOutput(word)
    endif
    if type == ''
      let type = FindDeclaredType(word)
    endif
    let clazz = FindClassType(type)
    let lines = split(system(s:normalize_command(s:javap_exec . ' ' . clazz)), '\v\n')
    for l in lines | echom l | endfor
  finally
    exe "lcd " . dirs.cwd_dir
  endtry
endfunction "}}}

" When the word under cursor is a Variable this method is used
" to find what is the type of the variable
fun! s:find_variable_type(variable) "{{{
  let type = s:findDeclaredTypeInMethod(a:variable)
  if type == ''
    let type = s:findDeclaredTypeInJavapOutput(a:variable)
  endif
  if type == ''
    let type = FindDeclaredType(a:variable)
  endif
  return type
endfunction "}}}

fun! s:clean_current() "{{{
  let base = expand('%:p:h')
  call s:delete_current_class_file(base)
endfunction "}}}

fun! s:find_Project_Base(base) "{{{
  let base_files = ['pom.xml', 'build.gradle', 'build.xml']
  for base_file in base_files
    let project_base = findfile(base_file, a:base . '.;' )
    if project_base != ''
      return fnamemodify(project_base, ':p:h')
    endif
  endfor
  return ''
endfunction "}}}

function! s:delete_current_class_file(base)
  let project_base = s:find_Project_Base(a:base)
  if project_base != ''
    let package = getline(searchpos("^package", 'bn')[0])
    let package = substitute(package, ';', '', '')
    let package = substitute(substitute(package, '\.', '/', 'g'),
          \'package\s\+', '', '')
    let package = substitute(package, '^\s\+\|\s\+$', '', 'g')
    let class_file = project_base . '/target/classes/' . package
    let class_file .= '/' . expand('%:t:r') . '.class'
    call delete(class_file)
    call feedkeys("\<C-l>")
    call feedkeys("\<C-l>")
    redraw
  endif
endfunction

fun! FindClassType(clazz) "{{{
  let line_import = FindImport(a:clazz)
  let clazz = matchstr(getline(line_import), '\v^import\s+\zs.*\ze\W')
  return clazz
endfunction "}}}

fun! FindImport(clazz) "{{{
  let a_class = a:clazz
  let expression = '\v^import .+<' . a_class . ';'

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
    silent f auto\ import\ list
    setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile number
    setlocal nonu
    call s:fill_buffer_imports(search_term)
    setl nomodifiable
    call s:mappings_for_auto_import_window(a:back_to_insert_mode)
  finally
    exe "lcd " . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:find_type_from_var_or_type(type_or_var) "{{{
    " Word under cursor is a variable
    " the totally weird cur_word[1]=='$' is because '$' has to be escaped
    if a:type_or_var =~# '\v^[a-z]' || a:type_or_var[1] == '$'
      let l:var_type = s:find_variable_type(a:type_or_var)
    else
    " Word under cursor is a Class/Interface
      let l:var_type = a:type_or_var
    endif
    return l:var_type
endfunction "}}}

fun! CreateDescribeWindow() "{{{
  let working_window = bufwinnr('%')
  let dirs = s:calculate_dirs()
  exe 'lcd ' . dirs.project_dir
  try
    let cur_word = s:get_cword_or_blank()
    if cur_word == ''
      return
    endif
    if cur_word !~# '^[A-Z]'
      let var_type = s:find_variable_type(cur_word)
    else
      let var_type = cur_word
    endif
    let full_class_name = FindClassType(var_type)
    keepalt bot new
    exe 'silent f describe\ ' . full_class_name
    let lines = s:exec_javap(full_class_name, 0)
    let lines = s:format_javap_output(lines)
    call map(lines, 'substitute(v:val, ''\vstatic final\s+'', '''', '''')')
    call setline(1, lines[0])
    let line_num = 1
    for line in lines[1:]
      call append(line_num, line)
      let line_num += 1
    endfor
  finally
    exe "lcd " . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:format_javap_output(lines) "{{{
    call filter(a:lines, 'v:val=~ ''\v^[[:space:]]+''')
    call map(a:lines, 'substitute(v:val, ''\v^\s+public\s+'', '''', '''')')
    call map(a:lines, 'substitute(v:val, ''\vjava\.lang\.'', '''', ''g'')')
    call map(a:lines, 'substitute(v:val, ''\v(\w+\.)+\ze\w+\W'', '''', '''')')
    call map(a:lines, 'substitute(v:val, ''\v<final>\s'', '''', '''')')
    return a:lines
endfunction "}}}

fun! s:get_cword_or_blank() "{{{
  let cur_line = getline(line('.'))
  "Zero based index for string operations
  let column = col('.') - 1
  if cur_line[column] =~ '\v[^[:alnum:]\$_]' || cur_line =~ '\v^$'
    return ''
  endif

  let last_col = s:find_last_word_column(column + 1)
  let first_col = s:find_first_word_column(column - 1)

  return substitute(cur_line[first_col : last_col], '\v\$', '\\$', 'g') | " yes, have to escape dollar sign
endfunction "}}}

fun! s:find_last_word_column(column, ...) "{{{
  let l:search_expr = '\v[^[:alnum:]\$_]'
  if len(a:000) > 0 && a:1
    let l:search_expr = '\v[^[:alnum:]\$_.]'
  endif

  let cur_line = getline(line('.'))
  if cur_line[a:column] =~ l:search_expr
        \ ||   a:column >= len(cur_line)
    return a:column - 1
  endif
  if len(a:000) > 0 && a:1
    return s:find_last_word_column(a:column + 1, a:1)
  endif
  return s:find_last_word_column(a:column + 1)
endfunction "}}}

fun! s:find_first_word_column(column, ...) "{{{
  let l:search_expr = '\v[^[:alnum:]\$_]'
  if len(a:000) > 0 && a:1
    let l:search_expr = '\v[^[:alnum:]\$_.]'
  endif

  let cur_line = getline(line('.'))
  if cur_line[a:column] =~ l:search_expr
    return a:column + 1
  endif
  if len(a:000) > 0 && a:1
    return s:find_first_word_column(a:column - 1, a:1)
  endif
  return s:find_first_word_column(a:column - 1)
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

" Alternation functions
fun! s:Alternate() "{{{
    let file_path = expand('%:p:h')
    if file_path =~ '.*\<test\>'
        call s:SwitchFromTest()
        return
    endif

    call s:SwitchToTest()
endfunction "}}}

fun! s:SwitchFromTest() "{{{
    let package_loc = search("^package", 'bn')
    if package_loc == 0
        echohl WarningMsg | echo 'NULL' | echohl None
        return
    endif
    let package = getline(package_loc)
    let file_path = expand('%:p:h')

    let path_prefix = substitute(file_path, '\W\zstest\ze\W', 'main', '')

    let test_name = expand('%:t:r')
    let full_path_one = path_prefix . '/' . substitute(test_name, 'Test', '', '') . '.java'
    let full_path_two = path_prefix . '/impl/' . substitute(test_name, 'Test', '', '') . 'Impl.java'
    let full_path_three = path_prefix . '/' . substitute(test_name, 'Test', '', '') . 'Impl.java'

    let paths = [full_path_one, full_path_two, full_path_three]

    if !filereadable(full_path_one) && !filereadable(full_path_two) && !filereadable(full_path_three)
        try
            call CreateFileToTest(paths, package)
        catch /CANCEL/
             echohl WarningMsg | echo "CANCEL" | echohl None
             return
        endtry
    endif

    for full_path in paths
        if filereadable(full_path) && filewritable(full_path)
            let file_to_test = full_path
            break
        endif
    endfor

    silent! exe 'e ' . file_to_test

endfunction "}}}

silent! fun! CreateFileToTest(paths, package) "{{{
    let message = ''
    for path_ in a:paths
        let message .= path_ . "\n"
    endfor

    echo a:paths
    let message .= 'None, Cancel'

    let choice = confirm('File will be?', message, 1)

    if choice == 0 || choice == len(a:paths) + 1
        throw "CANCEL"
    endif

    let path = a:paths[choice-1]
    let a_dir = join(split(path, '[\\/]')[:-2], '/')

    if !isdirectory(a_dir)
        call mkdir(a_dir, 'p')
    endif

    let package = a:package

    if a_dir =~ 'impl\W'
        let package .= '.impl'
    endif

    let class_name = split(split(path, '[\\/]')[-1], '\.')[0]

    call writefile([package
                \ , '', 'public class ' . class_name
                \ . '/*implements ' . substitute(class_name, 'Impl', '', ''), '*/ {'
                \ , '', '}', ''], path)
endfunction "}}}

fun! s:SwitchToTest() "{{{
    let package_loc = search("^package", 'bn')
    if package_loc == 0
        echohl WarningMsg | echo 'NULL' | echohl None
        return
    endif
    let package = getline(package_loc)
    let file_path = expand('%:p:h')

    let new_file_path = substitute(substitute(file_path, '\W\zsmain\ze\W', 'test', ''), '\W\zsimpl\(\W\|$\)', '', '')

    if !isdirectory(new_file_path)
        call mkdir(new_file_path, 'p')
    endif

    let test_name = substitute(expand('%:t:r'), '\(Impl\|Test\)$', '', '') . 'Test.java'
    let test_file = new_file_path . '/' . test_name

    if !filewritable(test_file) && !filereadable(test_file)
        call writefile([package, '', 'public class ' . split(test_name, '\.')[0] . ' {', '' , '}'], test_file)
    endif
    silent! execute 'e ' . test_file
endfunction "}}}

fun! s:clear_autocmds_insert_leave() "{{{
  augroup java_complete
    au!
  augroup END
endfunction "}}}

fun! s:prepare_completion() "{{{
  "Should I have to implement something like this?
  augroup java_complete 
    au! 
    au InsertLeave *.java pclose 
    au InsertLeave *.java set cfu=
    au InsertLeave *.java set cfu=
    au InsertLeave *.java call s:clear_autocmds_insert_leave()
  augroup END

  let col = getpos('.')[2] - 1
  let last_col = s:find_last_word_column(col, 1)
  let first_col = s:find_first_word_column(col, 1)
  let complete_expr = getline(line('.'))[first_col : last_col]

  if complete_expr !~ '\v\.'
    return " \<BS>"
  endif

  let var_name = matchstr(complete_expr, '\v.+\ze\.')
  let var_name = substitute(var_name, '\v\$', '\\&', 'g')

  let dirs = s:calculate_dirs()
  exe "lcd " . dirs.project_dir
  try
    if var_name =~# '\v^[a-z]' || var_name[1] == '$'
      let l:var_type = s:find_variable_type(var_name)
    else
      let l:var_type = var_name
    endif
    let full_class_name = FindClassType(var_type)
  finally
    exe 'lcd ' . dirs.cwd_dir
  endtry

  let l:lines = s:exec_javap(full_class_name, 0)
  let l:lines = s:format_javap_output(l:lines)

  let l:lines = s:prefilter_static(var_name, l:lines)
  let l:lines = s:filter_for_completion(l:var_type, l:lines)
  let l:completions = s:format_dict(l:lines)
  let s:completion_dict.lines = l:completions
  "this weird stuff is just to support '$' in variable names
  let s:completion_dict.col_start = first_col + 1 
        \ + len(substitute(var_name, '\\', '', 'g'))

  let cur_len = len(getline(line('.')))

  set cfu=Complete_Java_Fun
  return "\<C-x>\<C-u>"
endfunction "}}}

fun! s:format_dict(lines) "{{{
  "{word, abbr, menu, info, kind, icase, dup}
  "let l:lines = map(copy(a:lines), 'substitute(v:val, ''\v(.*'', '''', '''')')
  let l:completion = []
  for l:l in a:lines
    let l:word = substitute(l:l, '\v\(.{-}\)', '', '')
    let l:menu = matchstr(l:l, '\v(\(.*\))', '\1')
    let l:info = l:word . l:menu
    if l:info =~ '\v.+\(\s*\)$' | let l:info = ' ' | endif
    let complete_item = {'word': l:word,
          \ 'menu': l:menu,
          \ 'info': l:info,
          \ 'icase': 1,
          \ 'dup': 1}
    call add(l:completion, complete_item)
  endfor
  return l:completion
endfunction "}}}

fun! s:filter_for_completion(var_type, lines) "{{{
  "format lines starting with static
  call map(a:lines, 'substitute(v:val, ''^\v<static>\s'', '''', '''')')
  "filter constructor
  call filter(a:lines, 'v:val !~# ''\v^' . a:var_type . '\(''')
  call map(a:lines, 'substitute(v:val, ''^\v.{-}\s\ze.*'', '''', '''')')
  call map(a:lines, 'substitute(v:val, '';'', '''', '''')')
  return a:lines
endfunction "}}}

fun! Complete_Java_Fun(findstart, base) "{{{
  if a:findstart
    let cur_col = getpos('.')[2] - 1
    let line = getline(line('.'))
    while line[cur_col-1] =~? '\v^[a-z]$' && cur_col > 0
      let cur_col -= 1
    endwhile
    return cur_col
  endif
  let l:sexpr = '\v^' . a:base
  return filter(copy(s:completion_dict.lines), 'v:val["word"] =~? ''' . l:sexpr . '''')
endfunction "}}}

fun! s:prefilter_static(var_name, lines) "{{{
  let l:lines = a:lines
  if a:var_name =~# '\v^[A-Z].*'
    let l:lines = filter(l:lines, 'v:val =~ ''\v\s*static''')
  endif
  let l:lines = map(l:lines, 'substitute(v:val, ''\vstatic\s+|final\s+'', '''', ''g'')')
  return l:lines
endfunction "}}}

augroup command_on_save
  au!
  au BufWritePost *.java call CompileOnSave()
augroup END

"Not totally sure if dictionary is well suited for this behavior
let g:dict_javavim['methoddef'] = function('<SNR>' . s:sid . 'get_method_def')
let g:dict_javavim['strip_parens'] = function('<SNR>' . s:sid . 'strip_parens')
let g:dict_javavim['strip_to_plain_params'] = function('<SNR>' . s:sid . 'strip_to_plain_params')
let g:dict_javavim['def_variables_method'] = function('<SNR>' . s:sid . 'return_def_variables')

fun! s:autowrite_type_var() "{{{
  let l:pos = getpos('.')
  let l:col_ = s:find_first_word_column(l:pos[2]-3, 0)
  let l:candidate = getline(line('.'))[col_ :l:pos[2]-1]
  let l:needs_space = l:candidate =~ '\s$' ? 0 : 1
  if l:candidate =~# '^[A-Z]'
    let l:ret_val = (l:needs_space ? ' ' : '') .
          \ substitute(l:candidate, '^\w', '\l&', '')
  else
    let l:ret_val = repeat("\<BS>", len(l:candidate))
    let l:ret_val .= substitute(l:candidate, '^\w', '\u&', '')
    if l:needs_space
      let l:ret_val .= ' '
    endif
    let l:ret_val .= l:candidate
  endif
  return l:ret_val
endfunction "}}}



inoremap <expr> <C-g><C-e> <SID>autowrite_type_var()
inoremap <expr> <C-g>e     <SID>autowrite_type_var()

nnoremap g5 :call CreateDescribeWindow()<CR>

command! -buffer CompileOnSaveToggle call ToggleSettingCompileOnSave()
command! -buffer CacheCurrProjMaven call CacheThisMavenProj()
command! -buffer CreateIndex call CacheThisMavenProj() | call List_classes_cache()
command! -buffer IndexCache call List_classes_cache()
command! -buffer JavaC call JavaCBuffer()
command! -buffer Junit call JUnitCurrent()
command! -buffer Javap call Javapcword()
command! -buffer A call s:Alternate()
nnoremap <silent><buffer> g7 :call <SID>javap_current()<cr>
inoremap <silent><buffer> <C-g><C-p> <Esc>:call CreateAutoImportWindow(1)<cr>
inoremap <silent><buffer> <C-g>p <Esc>:call CreateAutoImportWindow(1)<cr>
nnoremap <silent><buffer> <C-g><C-p> :call CreateAutoImportWindow(0)<cr>
nnoremap <silent><buffer> <C-g>p :call CreateAutoImportWindow(0)<cr>
inoremap <silent><buffer> <expr> <C-g><C-n> <SID>prepare_completion()


