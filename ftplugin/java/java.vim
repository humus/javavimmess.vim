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
  try
    let paths = s:parse_mvn_output()
    call s:copy_files_to_cache(paths)
  finally
    exe "cd " . cwd_
  endtry
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

fun! JavacBuffer() "{{{
  let dirs = s:calculate_dirs()
  let javac = s:javac_core_command
  if expand('%:t') =~# '\vTest|IT'
    let javac = s:javac_test_command
  endif
  try
    execute 'lcd ' . dirs.project_dir
    call s:createclassesdirs()
    let output = system(s:normalize_command(javac . ' ' . expand('%')))
    redraw
    if output == ''
      echom 'OK'
      return 1
    else
      let lines = split(output, '\v\n')
      for l in lines | echom l | endfor
      return 0
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
    Javac
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
  let vars = filter(copy(javap_output), 'v:val =~ ''\v<' . a:var . ';$''')
  call map(vars, 'matchstr(v:val, ''\v^.+\.\zs\S+\ze\s+[\$_[:alnum:]]+;$'')')
  if empty(vars)
    return ''
  else
    return vars[0]
  endif
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
  "Obtain current clazz and package to check if this is a test class
  let l:cur_class = s:current_clazz()
  let l:cur_package = matchstr(l:cur_class, '\v^.+\ze\.\w+$')
  let l:cur_class = matchstr(l:cur_class, '\v^.+\.\zs\S+$')
  if l:cur_class =~# a:clazz . 'Test'
    "When it is a test class must check before
    "if class under test is in the same package
    let l:clazz_type = l:cur_package . '.' . a:clazz
    if s:source_of_clazz_exists(l:clazz_type)
      return l:clazz_type
    endif
  endif
  let line_import = FindImport(a:clazz)
  return matchstr(getline(line_import), '\v^import\s+\zs.*\ze\W')
endfunction "}}}

fun! s:source_of_clazz_exists(clazz_type) "{{{
  let path = 'src/main/java/'
  let more_on_path = substitute(a:clazz_type, '\v\.', '/', 'g')
  let path .= more_on_path . '.java'
  return filereadable(path)
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
    keepalt bel new
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
    keepalt bel new
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
  call filter(a:lines, 'v:val=~''\v^[[:space:]]+''')
  call map(a:lines, 'substitute(v:val, ''\v^\s+public\s+'', '''', '''')')
  call map(a:lines, 'substitute(v:val, ''\vjava\.lang\.'', '''', ''g'')')
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

  return substitute(cur_line[first_col : last_col],
        \ '\v\$', '\\$', 'g') | " yes, have to escape dollar sign
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
  if cur_line[a:column] =~ l:search_expr || a:column < 0
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

fun! s:clear_autocmds_java_complete() "{{{
  augroup java_complete
    au!
  augroup END
endfunction "}}}

fun! s:manage_cursor_after_complete() "{{{
  let possible_paren = getline(line('.'))[getpos('.')[2] - 2]
  let ret_expr = "\<CR>"
  if pumvisible() && possible_paren =~ '\v\)'
    let ret_expr = "\<C-Y>\<Left>"
  elseif pumvisible()
    let ret_expr = "\<C-Y>"
  endif
  return ret_expr
endfunction "}}}

fun! s:prepare_completion() "{{{
  "Should I have to implement something like this?
  augroup java_complete 
    au! 
    au InsertLeave *.java pclose
    au InsertLeave *.java set cfu=
    au InsertLeave *.java silent! iunmap <buffer> <cr>
    au InsertLeave *.java silent! iunmap <buffer> <tab>
    au InsertLeave *.java call s:clear_autocmds_java_complete()
  augroup END

  inoremap <buffer> <expr> <cr> <SID>manage_cursor_after_complete()
  inoremap <buffer> <expr> <tab> <SID>manage_cursor_after_complete()

  let col = getpos('.')[2] - 1
  let last_col = s:find_last_word_column(col, 1)
  let first_col = s:find_first_word_column(col-1, 1)
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

    let l:lines = s:exec_javap(full_class_name, 0)
    let l:lines = s:format_javap_output(l:lines)
    let l:lines = s:prefilter_static(var_name, l:lines)
    let l:lines = s:filter_for_completion(l:var_type, l:lines)
    let l:completions = s:format_dict(l:lines)
    let s:completion_dict.lines = l:completions
    "this weird stuff is just to support '$' in variable names
    let s:completion_dict.col_start = first_col + 1 
          \ + len(substitute(var_name, '\\', '', 'g'))

  finally
    exe 'lcd ' . dirs.cwd_dir
  endtry

  set cfu=Complete_Java_Fun
  return "\<C-x>\<C-u>"
endfunction "}}}

fun! s:format_dict(lines) "{{{
  "{word, abbr, menu, info, kind, icase, dup}
  let l:completion = []
  for l:l in a:lines
    let l:word = substitute(l:l, '\v\(\zs.{-}\ze\)', '', '')
    let l:word = substitute(l:word, '\v\s*throws .*$', '', '')
    let l:menu = matchstr(l:l, '\v(\(.*\))', '\1')
    let l:info = l:word[:-3] . l:menu
    let l:info .= matchstr(l:l, '\v(\s*throws\s+.*)?$')
    if l:info =~ '\v.+\(\s*\)\s*$' | let l:info = '' | endif
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
  call map(a:lines, '<SNR>'.s:sid.'apply_substitutions(v:val)')
  return a:lines
endfunction "}}}

fun! s:apply_substitutions(line) "{{{
  "format lines starting with static
  let l:line = substitute(a:line, '\v^<static>\s', '', '')
  let l:line = substitute(l:line, '\vabstract\s', '', '')
  let l:line = substitute(l:line, '\v^.{-}\s\ze.*', '', '') "to remove public keyword
  let l:line = substitute(l:line, ';', '', '')
  return l:line
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

fun! s:jmess_sid() dict "{{{
  echo s:sid . '	<-----'
endfunction "}}}
"Not totally sure if dictionary is well suited for this behavior
let g:dict_javavim['methoddef'] = function('<SNR>' . s:sid . 'get_method_def')
let g:dict_javavim['strip_parens'] = function('<SNR>' . s:sid . 'strip_parens')
let g:dict_javavim['strip_to_plain_params'] = function('<SNR>' . s:sid . 'strip_to_plain_params')
let g:dict_javavim['def_variables_method'] = function('<SNR>' . s:sid . 'return_def_variables')

fun! s:autowrite_type_var() "{{{
  let l:pos = getpos('.')
  let l:col_1 = s:find_first_word_column(l:pos[2]-3)
  let l:col_2 = s:find_last_word_column(l:pos[2]-3)
  let l:candidate = getline(line('.'))[l:col_1 : l:col_2]
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

fun! s:autowrite_new_from_var() "{{{
  let l:pos = getpos('.')
  let l:col_ = s:find_first_word_column(l:pos[2]-3, 0)
  let l:candidate = getline(line('.'))[col_ : l:pos[2]-1]
  if l:candidate =~# '^[a-z]'
    let l:space_or_blank = l:candidate =~ '\s$' ? '' : ' '
    let l:ret_val = l:space_or_blank . "= new "
          \ . substitute(l:candidate, '^\w', '\u&', '')
          \ . "();\<Left>\<Left>"
  else
    let l:ret_val = " \<BS>"
  endif
  return l:ret_val
endfunction "}}}

fun! s:check_for_dot_class() "{{{
  let l:class = s:current_clazz()
  let l:path = s:get_class_file_path(l:class)
    return filereadable(l:path)
endfunction "}}}

fun! s:analyze_javap_output() "{{{
  let dirs = s:calculate_dirs()
  try
    execute 'lcd ' . dirs.project_dir
    if !s:check_for_dot_class()
      if !JavacBuffer()
        echohl WarningMsg | echo 'Class has errors' | echohl NONE
        return
      endif
    endif
    let l:output = s:exec_javap(s:current_clazz(), 1)
    let l:props = s:get_properties(l:output)
    let l:methods = s:get_setters_getters(l:output)
    call s:append_getters_setters(l:props, l:methods)
  finally
    execute 'lcd ' . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:append_getters_setters(props, methods) "{{{
  let l:generated_methods = []
  let l:lines_to_append = []
  for l:prop in a:props
    let l:getter_prefix = l:prop.type . ' '
    let l:getter_prefix .= substitute(l:prop.name, '^.', 'get\u&', '')
    let l:setter_prefix = substitute(l:prop.name, '^.', 'void set\u&', '')
    let l:prop.getter = s:check_for_getter_setter(l:getter_prefix, a:methods)
    let l:prop.setter = s:check_for_getter_setter(l:setter_prefix, a:methods)
    let l:lines_to_append += s:create_getter_lines(l:prop, l:getter_prefix)
    let l:lines_to_append += s:create_setter_lines(l:prop, l:setter_prefix)
  endfor
  if len(l:lines_to_append) > 0
    let l:line = s:calculate_getter_setter_pos()
    call append(l:line, l:lines_to_append)
  endif
endfunction "}}}

fun! s:create_getter_lines(prop, prefix) "{{{
  let l:lines = []
  if a:prop.getter
    call add(l:lines, '    public ' . a:prefix . '() {')
    call add(l:lines, '        return ' . a:prop.name . ';')
    call add(l:lines, '    }')
    call add(l:lines, '')
  endif
  return l:lines
endfunction "}}}

fun! s:create_setter_lines(prop, prefix) "{{{
  let l:lines = []
  if a:prop.setter
    call add(l:lines, '    public ' . a:prefix . '(' .
          \ a:prop.type . ' ' . a:prop.name
          \ . ') {')
    call add(l:lines, '        this.' . a:prop.name . '='. a:prop.name .';')
    call add(l:lines, '    }')
    call add(l:lines, '')
  endif
  return l:lines
endfunction "}}}

fun! s:check_for_getter_setter(method, methods) "{{{
  if index(a:methods, a:method) == -1
    return 1
  else
    return 0
  endif
endfunction "}}}

fun! s:calculate_getter_setter_pos() "{{{
  let l:lines = []
  call add(l:lines, searchpos('\v^}$')[0])
  call add(l:lines, searchpos('\v^\s+public boolean equals')[0])
  call add(l:lines, searchpos('\v^\s+public int hashCode')[0])
  call add(l:lines, searchpos('\v^\s+public String toString')[0])
  let l:lines = filter(l:lines, 'v:val > 0')
  call sort(l:lines)
  return l:lines[0] - 1
endfunction "}}}

fun! s:get_properties(javap_output) "{{{
  let l:props = filter(copy(a:javap_output), 'v:val =~? ''\v(private|protected).+[[:alnum:]];$''')
  let l:props = map(l:props, 'substitute(v:val, ''\v^\s+(private|protected)\s+([[:alnum:]\$_]+\.)*'', '''', '''')')
  let l:dicts = []
  for l in l:props
    let l:match = matchlist(l, '\v(\w+)\s+(\w+);')
    call add(l:dicts, {'type': l:match[1], 'name': l:match[2]})
  endfor
  return l:dicts
endfunction "}}}

fun! s:get_setters_getters(javap_output) "{{{
  let l:methods = filter(copy(a:javap_output), 'v:val =~? ''\v[sg]et\w+\(.*\);''')
  let l:methods = map(l:methods, 'substitute(v:val, ''\v^\s+public %(\w+\.)*(\w+%(\.)@!.+\s\S+)\(.*$'', ''\1'', '''')')
  return l:methods
endfunction "}}}

fun! s:get_class_file_path(class_file) "{{{
  let l:path = substitute(a:class_file, '\v\.', '/', 'g') . '.class'
  let l:path = 'target/classes/'.l:path
  return l:path
endfunction "}}}

fun! VimJMessSID() "{{{
  return s:sid
endfunction "}}}

inoremap <expr> <C-g><C-e> <SID>autowrite_type_var()
inoremap <expr> <C-g>e     <SID>autowrite_type_var()
inoremap <expr> <C-g>E     <SID>autowrite_new_from_var()
nnoremap g5 :call CreateDescribeWindow()<CR>

command! FileIndexSort call s:sort_file_index_cd()
command! -buffer CompileOnSaveToggle call ToggleSettingCompileOnSave()
command! -buffer CacheCurrProjMaven call CacheThisMavenProj()
command! -buffer CreateIndex call CacheThisMavenProj() | call List_classes_cache()
command! -buffer IndexCache call List_classes_cache()
command! -bar -buffer Javac call JavacBuffer()
command! -bar -buffer Junit call JUnitCurrent()
command! -bar -buffer Javap call Javapcword()
command! -buffer A call s:Alternate()
nnoremap <silent><buffer> g7 :call <SID>javap_current()<cr>
inoremap <silent><buffer> <C-g><C-i> <Esc>:call CreateAutoImportWindow(1)<cr>
inoremap <silent><buffer> <C-g>i <Esc>:call CreateAutoImportWindow(1)<cr>
nnoremap <silent><buffer> <C-g><C-i> :call CreateAutoImportWindow(0)<cr>
nnoremap <silent><buffer> <C-g>p :call CreateAutoImportWindow(0)<cr>
inoremap <silent><buffer> <expr> <C-g><C-n> <SID>prepare_completion()
