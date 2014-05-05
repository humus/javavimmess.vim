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
let s:prompt_height = 4
exe s:let_sid

let s:completion_dict = {}

let s:method_def_expr =
\ '\v^%(\t|    )%((private |protected |public )%((public|private|protected)@!))?[[:alnum:]]+(\<.+\>)?[[:space:]\n]{1,}[[:alnum:]\$_]+\s{-}\('
let s:method_bodystart_expr = '\v\{'
let s:matching_properties = '\v^\s+(protected|private)( final)@!( static)@!\s+(.+)\s+[^[:space:]]+;\s*$'
let s:match_highlight_suffix = '\s+(protected|private)( final)@!( static)@!\s+(.+)\s+\zs[^[:space:]]+\ze;\s*$'

fun! s:cacheThisMavenProj() abort "{{{
  let l:adir = fnamemodify(findfile('pom.xml', '.;'), ':h')
  if l:adir =~ '\v^$' | let l:adir = '.' | endif
  if l:adir !~ '\v/$' | let l:adir .= '/' | endif
  let l:cmd_height = &cmdheight
  set cmdheight=3
  let l:is_regenerated = s:prompt_regenerate_cache(l:adir)
  exe "set cmdheight=" . l:cmd_height
  if l:is_regenerated
    call s:populate_cache(l:adir)
  endif
endfunction "}}}

fun! s:prompt_regenerate_cache(adir) "{{{
  let l:adir = a:adir . '.cache'
  let l:regenerated=1
  if isdirectory(l:adir)
    echo 'Do you want to regenerate cache?'
    echo '================================'
    echo 'y/n '
    let l:response = nr2char(getchar())
    if l:response =~? 'y'
      call s:delete_dir(l:adir)
    else
      redraw | echo "Cache preserved"
      let l:regenerated = 0
    endif
  endif
  return l:regenerated
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
  let l:cwd_ = getcwd()
  exe "cd " . a:a_dir
  try
    let l:paths = s:parse_mvn_output()
    call s:save_snapshots_ref(l:paths)
    call s:copy_files_to_cache(l:paths)
  finally
    exe "cd " . l:cwd_
  endtry
endfunction "}}}

fun! s:parse_mvn_output() "{{{
  let l:mvn_output = system('mvn dependency:build-classpath')
  let l:lines = split(l:mvn_output, '\n')
  let l:line = filter(l:lines, 'v:val =~ ''\vjar[;:]'' && v:val !~ ''\vWARNING''')[0]
  let l:paths = split(l:line, '\v(^C|;C)@<![:;]')
  return l:paths
endfunction "}}}

fun! s:save_snapshots_ref(paths) "{{{
  let l:paths=map(copy(a:paths), 'fnamemodify(v:val, '':t'') . ''	 '' . v:val')
  call filter(l:paths, 'v:val =~ ''\vSNAPSHOT''')
  call writefile(l:paths, '.cache/jarfile_and_paths.txt')
endfunction "}}}

fun! s:update_jar_snapshots() "{{{
  let l:dirs = s:calculate_dirs()
  exe "lcd " . l:dirs.project_dir
  let l:file_refs='.cache/jarfile_and_paths.txt'
  try
    if filereadable(l:file_refs)
      let l:lines = readfile(l:file_refs)
      let l:counter=0
      for l in l:lines
        let l:cache_file = '.cache/' . matchstr(l, '\v^[^	]+\ze	')
        let l:repo_file = matchstr(l, '\v^[^	]+\s+\zs\S.+')
        if getftime(l:cache_file) < getftime(l:repo_file)
          call delete(l:cache_file)
          call s:copy_file(l:repo_file, l:cache_file)
          let l:counter+=1
        endif
      endfor
      if l:counter
        echo 'updated: ' . l:counter . ' jars'
      endif
    endif
  finally
    exe 'lcd ' . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:copy_file(source, dest) "{{{
  if has('win32')
    call system('copy ' . substitute(a:source, '\v/', '\\', 'g') . ' ' . substitute(a:dest, '\v/', '\\', 'g'))
  else
    call system('cp ' . a:source . ' ' . a:dest)
  endif
endfunction "}}}

fun! s:copy_files_to_cache(files) "{{{
  if has('win32')
    call s:exec_copies_win32(a:files)
  else
    call s:exec_copies(a:files)
  endif
endfunction "}}}

fun! s:exec_copies_win32(files) "{{{
  let l:len_of_files = len(a:files)
  let l:files_to_copy = []
  let l:partial_lists = s:create_sublists(a:files, 25)
  let l:counter = 0
  for files_to_copy in l:partial_lists
    call s:exec_copy_command_win32(l:files_to_copy)
    let l:counter += len(l:files_to_copy)
    redraw | echo l:counter . ' / ' . l:len_of_files
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
  let l:counter = 0
  for l:sublist in a:file_sublists
    call map(l:sublist, 's:str_jartf_call(v:val, ''findstr'')')
    " && echo on <-- it's added because system(...) ignores last command
    " after "&&" I don't know why
    let l:command = join(l:sublist, ' && ') . ' && echo on'
    call system(l:command)
    let l:counter += len(l:sublist)
    redraw | echom l:counter ' / ' . a:total
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

fun! s:list_classes_cache() "{{{
  let l:dirs = s:calculate_dirs()
  exe "lcd " . l:dirs.project_dir
  lcd .cache
  try
    let l:jar_files = split(globpath('.', "*.jar"), '\n')
    let l:sublists = s:create_sublists(l:jar_files, 15)
    if has('win32')
      call s:list_classes_win32(l:sublists, len(l:jar_files))
    else
      call s:list_classes(l:sublists, len(l:jar_files))
    endif
    call s:sort_file_index()
  finally
    exe "lcd " . dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:calculate_dirs() "{{{
  let l:project_dir = fnameescape(matchstr(findfile('pom.xml', '.;'), '\v.+\zepom\.xml$'))
  if l:project_dir == ''
    let l:project_dir = '.'
  endif
  let l:cwd_dir = fnameescape(getcwd())
  return {'project_dir': l:project_dir, 'cwd_dir': l:cwd_dir}
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
  let l:stopline = searchpair(
        \ s:method_def_expr 
        \ , ''
        \ , '\v^%(\t|    )}'
        \ , 'bn')
  let l:search_expr = '\v^\s+(final\s|for\s*\(\s*)?\S+.*(\=|:)@<!\s?' . a:variable . '\s*[[:punct:];=].*$'
  let l:def_line = search(l:search_expr, 'cbnW', l:stopline)
  let l:def_str = substitute(getline(l:def_line), '\v<for>\s*\(', '', '')
  let l:type= substitute(
        \ substitute(
        \ matchstr(l:def_str,'\v^\s+(final\s)?\S+.{-}\ze\s' . a:variable . '.*')
        \ , '\v\<[^>]\>', '', '')
        \ , '\v^\s+|\s+$', '', 'g')

  return l:type
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

fun! s:delete_current_class_file(base) "{{{
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
endfunction "}}}

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
  "When line_import is zero it means the class is in the same package
  if line_import == 0
    return l:cur_package . '.' . a:clazz
  endif
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
  let l:expression = '\v^import .+<' . a_class . ';'

  let _pos = searchpos(l:expression, 'bn')[0]
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
        \ || a:column >= len(cur_line)
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

  let l:paths = [full_path_one, full_path_two, full_path_three]

  if !filereadable(full_path_one) && !filereadable(full_path_two) && !filereadable(full_path_three)
    try
      call CreateFileToTest(l:paths, package)
    catch /CANCEL/
      echohl WarningMsg | echo "CANCEL" | echohl None
      return
    endtry
  endif

  for full_path in l:paths
    if filereadable(full_path) && filewritable(full_path)
      let file_to_test = full_path
      break
    endif
  endfor

  silent! exe 'e ' . file_to_test

endfunction "}}}

fun! CreateFileToTest(paths, package) "{{{
  let message = ''
  for path_ in a:paths
    let message .= path_ . "\n"
  endfor

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
    au InsertLeave *.java silent! iunmap <buffer> <C-y>
    au InsertLeave *.java call s:clear_autocmds_java_complete()
  augroup END

  inoremap <buffer> <expr> <cr> <SID>manage_cursor_after_complete()
  inoremap <buffer> <expr> <C-y> <SID>manage_cursor_after_complete()
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
  let var_name = substitute(var_name, '\vthis\.', '', '')
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
  let l:line = substitute(l:line, '\v<synchronized>\s', '', '')
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

fun! s:getters_setters() "{{{
  let l:dirs = s:calculate_dirs()
  try
    execute 'lcd ' . l:dirs.project_dir
    let l:pos = getpos('.')
    let l:props = s:get_property_lines()
    call map(l:props, '<SID>clean_property(v:val)')
    let l:lines_to_append = s:define_getset_lines(l:props)
    if len(l:lines_to_append) > 0
      let l:line = s:calculate_getter_setter_pos()
      call append(l:line, l:lines_to_append)
    endif
    cal cursor(pos[1], pos[2])
  finally
    execute 'lcd ' . l:dirs.cwd_dir
  endtry
endfunction "}}}

fun! s:extract_types_from_props(props) "{{{
  let l:type_defs=map(copy(a:props), 'substitute(v:val, ''\s+\S+$'', '''', '''')')
  let l:types=[]
  let l:type_expr='\v(\$+\w+|\w+|\w+\$+|\$+\w+\$+\w*)+'
  let l:count=0
  for l:type_def in l:type_defs
    let l:tmp = l:type_def
    while match(l:tmp, l:type_expr) >= 0
      let l:type = matchstr(l:tmp, l:type_expr)
      call add(l:types, l:type)
      let l:tmp=substitute(l:tmp, l:type_expr, '', '')
      let l:count+=1
      if l:count > 1000
        throw 'SUPERERROR'
      endif
    endwhile
  endfor
  return l:types
endfunction "}}}

fun! s:get_property_lines() "{{{
  let l:props = []
  for line in range(1, line('$'))
    if getline(line) =~# s:matching_properties
      call add(l:props, getline(line))
    endif
  endfor
  return l:props
endfunction "}}}

fun! s:get_property_line_numbers() "{{{
  let l:line_numbers = []
  for line in range(1, line('$'))
    if getline(line) =~# s:matching_properties
      call add(l:line_numbers, line)
    endif
  endfor
  return l:line_numbers
endfunction "}}}


fun! s:define_getset_lines(props) "{{{
  let l:lines_to_append = []
  for prop in a:props
    let l:lines_to_append += s:define_lines_for_property(prop)
  endfor
  return l:lines_to_append
endfunction "}}}

fun! s:define_lines_for_property(prop) "{{{
  let l:getter_line = substitute(a:prop,
        \ '\v(.+)\s([^[:space:]]+)$',
        \ 'public \1 get\u\2() {', '')
  let l:setter_line = substitute(a:prop,
        \ '\v(.+)\s([^[:space:]]+)$',
        \ 'public void set\u\2(\1 \2) {', '')
  let l:getter_lines = s:provide_getter_lines(l:getter_line, a:prop)
  let l:setter_lines = s:provide_setter_lines(l:setter_line, a:prop)
  return l:getter_lines + l:setter_lines
endfunction "}}}

fun! s:provide_getter_lines(getter_line, prop) "{{{
  if s:find_gettersetter(a:getter_line)
    return []
  endif

  let l:indent = &et ? '    ':'	'
  let l:definition = l:indent . a:getter_line . ':'
  let l:definition .= substitute(a:prop,
        \ '\v(.+)\s([^[:space:]]+)$',
        \ repeat(l:indent, 2) . 'return \2;', '')
  let l:definition .= ':' . l:indent . '}::'
  return split(l:definition, ':')
endfunction "}}}

fun! s:provide_setter_lines(setter_line, prop) "{{{
  if s:find_gettersetter(a:setter_line)
    return []
  endif

  let l:indent = &et ? '    ':'	'
  let l:definition = l:indent . a:setter_line . ':'
  let l:definition .= substitute(a:prop,
        \ '\v(.+)\s([^[:space:]]+)$',
        \ repeat(l:indent, 2) . 'this.\2 = \2;', '')
  let l:definition .= ':' . l:indent . '}::'
  return split(l:definition, ':')
endfunction "}}}

fun! s:find_gettersetter(getsetline) "{{{
  let l:expr = '\v' . a:getsetline
  let l:expr = substitute(l:expr, '\v\{', '[{]', '')
  let l:expr = substitute(l:expr, '\v\(\zs.{-}\ze\)', '[[:space:]\\n]*[^\)]*.{-}', '')
  let l:expr = substitute(l:expr, ' ', '\\s+', 'g')
  let l:expr = substitute(l:expr, '\v[<>()]', '\\&', 'g')
  let g:exp = l:expr
  return search(l:expr, 'nw')
endfunction "}}}

fun! s:clean_property(prop) "{{{
  let l:prop = substitute(a:prop, '\v^\s+(private|protected) ', '', '')
  let l:prop = substitute(l:prop, '\v;\s*$', '', '')
  let l:prop = substitute(l:prop, '\v\s*\=.*$', '', '')
  return l:prop
endfunction "}}}

fun! s:calculate_getter_setter_pos() "{{{
  let l:lines = []
  call add(l:lines, search('\v^}\s*$'))
  call add(l:lines, search('\v^\s+public boolean equals'))
  call add(l:lines, search('\v^\s+public int hashCode'))
  call add(l:lines, search('\v^\s+public String toString'))
  return s:find_first_line(l:lines)
endfunction "}}}

fun! s:calculate_hashcode_pos() "{{{
  let l:lines = []
  call add(l:lines, search('\v^}$', 'wcn'))
  call add(l:lines, search('\v^\s+public String toString', 'wcn'))
  return s:find_first_line(l:lines)
endfunction "}}}

fun! s:calculate_equals_pos() "{{{
  let l:lines = []
  call add(l:lines, search('\v^}$', 'wcn'))
  call add(l:lines, search('\v^\s+public String toString', 'wcn'))
  call add(l:lines, search('\v^\s+public int hashCode', 'wcn'))
  return s:find_first_line(l:lines)
endfunction "}}}

fun! NumCompare(i1, i2)
  return a:i1 - a:i2
endfun

fun! s:find_first_line(lines) "{{{
  let l:lines = filter(a:lines, 'v:val > 0')
  let l:lines = sort(l:lines, "NumCompare")
  return l:lines[0] - 1
endfunction "}}}

fun! s:gen_equals() "{{{
  let l:pos = getpos('.')
  let l:equals_l = s:search_equals()
  if l:equals_l > 0
    echohl WarningMsg | echo 'equals alreadyExists' | echohl None
    return
  endif
  let l:properties = s:handle_props_for_stdmethods('Include property in Equals?')
  if !empty(l:properties)
    call s:append_equals(l:properties)
  else
    echohl WarningMsg | echo 'equals not generated' | echohl None
  endif
  call cursor(l:pos[1], l:pos[2])
endfunction "}}}

fun! s:gen_hashcode() "{{{
  let l:pos = getpos('.')
  let to_hashcode_l = s:search_hashcode()
  if to_hashcode_l > 0
    echohl WarningMsg | echo 'hashCode alreadyExists' | echohl None
    return
  endif
  let l:properties = s:handle_props_for_stdmethods('Include property in hashCode?')
  if !empty(l:properties)
    call s:append_hashcode(l:properties)
  else
    echohl WarningMsg | echo 'hashCode not generated' | echohl None
  endif
  call cursor(l:pos[1], l:pos[2])
endfunction "}}}

fun! s:gen_tostring() "{{{
  let l:pos = getpos('.')
  let to_string_l = s:search_tostring()
  if to_string_l > 0
    echohl WarningMsg | echo 'toString alreadyExists' | echohl None
    return
  endif
  let l:properties = s:handle_props_for_stdmethods('Include property in toString?')
  if !empty(l:properties)
    call s:append_tostring(l:properties)
  else
    echohl WarningMsg | echo 'toString not generated' | echohl None
  endif
  call cursor(l:pos[1], l:pos[2])
endfunction "}}}

fun! s:handle_props_for_stdmethods(prompt) "{{{
  let l:prop_line_numbers = s:get_property_line_numbers()
  let l:cmdheight = &cmdheight
  let &cmdheight = s:prompt_height
  set cul
  try
    let l:properties = s:prompt_for_generated_method(l:prop_line_numbers
          \, a:prompt)
  finally
    let &cmdheight = l:cmdheight
  endtry
  set nocul
  return l:properties
endfunction "}}}

fun! s:append_equals(properties) "{{{
  let l:indent = &et ? '    ' : '	'
  call s:ensure_import('org.apache.commons.lang.builder.EqualsBuilder')
  let l:method = [l:indent.'public boolean equals(Object o) {',
        \ repeat(l:indent, 2).'if (o == null) { return false; }',
        \ repeat(l:indent, 2).'if (o == this) { return true; }',
        \ repeat(l:indent, 2).'if (this.getClass() != o.getClass()) { return false; }',
        \ repeat(l:indent, 2).s:get_class_name() . ' other = ' .
        \ '(' . s:get_class_name() . ')o;',
        \ repeat(l:indent, 2).'return new EqualsBuilder()']
  for l:prop in a:properties
    let l:str_body = [repeat(l:indent, 4),
          \'.append(this.', l:prop, ', other.' , l:prop, ')']
    call add(l:method, join(l:str_body, ''))
  endfor
  call add(l:method, repeat(l:indent, 4).'.isEquals();')
  call add(l:method, l:indent . '}')
  call add(l:method, '')
  let l:line = s:calculate_equals_pos()
  call append(l:line, l:method)
endfunction "}}}

fun! s:get_class_name() "{{{
  let l:expr = '\v^public class \zs\w+\ze'
  let l:line = search(l:expr, 'bnw')
  if l:line == 0
    throw 'Something is wrong with java file'
  endif
  return matchstr(getline(l:line), l:expr)
endfunction "}}}

fun! s:append_hashcode(properties) "{{{
  let l:indent = &et ? '    ' : '	'
  call s:ensure_import('org.apache.commons.lang.builder.HashCodeBuilder')
  let l:method = [l:indent.'public int hashCode() {', 
        \ repeat(l:indent, 2).'return new HashCodeBuilder(7, 3)']
  for l:prop in a:properties
    let l:str_body = [repeat(l:indent, 4),
          \'.append(', l:prop, ')']
    call add(l:method, join(l:str_body, ''))
  endfor
  call add(l:method, repeat(l:indent, 4) . '.hashCode();')
  call add(l:method, l:indent . '}')
  call add(l:method, '')
  call cursor(line('$'), 1)
  let l:line = s:calculate_hashcode_pos()
  call append(l:line, l:method)
endfunction "}}}

fun! s:append_tostring(properties) "{{{
  let l:indent = &et ? '    ' : '	'
  call s:ensure_import('org.apache.commons.lang.builder.ToStringBuilder')
  let l:method = [l:indent.'public String toString() {', 
        \ repeat(l:indent, 2).'return new ToStringBuilder(this)']
  for l:prop in a:properties
    let l:str_body = [repeat(l:indent, 4),
          \'.append("', l:prop, '"', ', ', l:prop, ')']
    call add(l:method, join(l:str_body, ''))
  endfor
  call add(l:method, repeat(l:indent, 4) . '.toString();')
  call add(l:method, l:indent . '}')
  call add(l:method, '')
  call cursor(line('$'), 1)
  call search('\v^\}\s*$', 'bc')
  call append(line('.')-1, l:method)
endfunction "}}}

fun! s:search_hashcode() "{{{
  return s:search_std_method('\v^\s+public\s+int\s+hashCode')
endfunction "}}}

fun! s:search_equals() "{{{
  return s:search_std_method('\v^\s+public\s+boolean\s+equals')
endfunction "}}}

fun! s:search_tostring() "{{{
  return s:search_std_method('\v^\s+public\s+String\s+toString')
endfunction "}}}

fun! s:search_std_method(method_expr) "{{{
  let l:pos = getpos('.')
  call cursor(line('$'), 1)
  let l:found = search(a:method_expr, 'bn')
  call cursor(l:pos[1], l:pos[2])
  return l:found
endfunction "}}}

fun! s:ensure_import(clazz) "{{{
  call cursor(line('$'), 1)
  let exists_import = search('\v^import\s+' . a:clazz, 'bn')
  if !exists_import
    let l:line = search('\v^(package[^;]+;|import[^;]+;)', 'bn')
    if l:line == 1
      call append(1, '')
      let l:line += 1
    endif
    call append(l:line, 'import ' . a:clazz . ';')
  endif
endfunction "}}}

fun! s:prompt_for_generated_method(lines, prompt) "{{{
  let l:responses = []
  let l:response = ''
  echohl Question
  for ln in a:lines
    call cursor(ln, 1)
    let prop = matchstr(getline(ln), '\v.+\s\zs[^;]+\ze;')
    let l:highlighted = matchadd('Question', join(['\v%', ln, 'l^', s:match_highlight_suffix], ''))
    if l:response != 'a'
      let l:response = s:prompt_while_invalid(a:prompt)
    endif
    call matchdelete(l:highlighted)
    if or(l:response == 'y', l:response == 'a')
      call add(l:responses, prop)
    endif
    if l:response == 'q'
      let l:responses = []
      let l:response = 'd'
    endif
    if l:response == 'd'
      break
    endif
  endfor
  echohl None
  return l:responses
endfunction "}}}

fun! s:prompt_while_invalid(promptstr) "{{{
  redraw
  let &cmdheight = s:prompt_height
  echo a:promptstr
  echo "y/n/a/d/q\n"
  let l:response=tolower(nr2char(getchar()))
  let &cmdheight=1
  if l:response !~ "\\v[ynadq\<Esc>]"
    call s:prompt_while_invalid(a:promptstr)
  endif
  return l:response
endfunction "}}}

fun! s:serial_ver() "{{{
  let l:line_serial_ver=search('\v^\s+(private )?static final long serialVersionUID.*', 'n')
  if l:line_serial_ver != 0
    echohl warningmsg | echo 'already has serialVersionUID' | echohl none
    return
  endif
  let serial_ver=s:find_serial_ver()
  if serial_ver !~ '\v\s+private static'
    echohl warningmsg | echo 'Class not serializable' | echohl none
    return
  endif
  call s:append_serial_ver(serial_ver)
endfunction "}}}

fun! s:append_serial_ver(serialver) "{{{
  let l:lines = ['', a:serialver, '']
  let l:public_class_line = search('\v^public class \S+.*', 'n')
  call append(l:public_class_line, l:lines)
endfunction "}}}

fun! s:find_serial_ver() "{{{
  let l:fqcn=s:search_package() . '.' . expand('%:t:r')
  let l:indent=&et? '    ' : "\t"
  let l:pom_xml=findfile('pom.xml', expand('%:p:h').';')
  let l:base_dir=fnamemodify(l:pom_xml, ':h')
  let l:cmd='serialver -classpath ' . l:base_dir .
        \ '/target/classes;' . l:base_dir .
        \ '/target/test-classes;' . l:base_dir .
        \ '/.cache/*;' . l:base_dir . ' '
        \ . l:fqcn
  echom l:cmd
  let l:serial_ver=l:indent . 'private ' . matchstr(system(l:cmd), '\v^[^:]+:\s+\zs.+')
  let l:serial_ver=substitute(l:serial_ver, "\n", '', '')
  return l:serial_ver
endfunction "}}}


fun! s:search_package() "{{{
  for line_nr in range(line('$'))
    let l:line = getline(line_nr)
    if  l:line =~ '\v^package.*'
      return matchstr(l:line, '\vpackage \zs.+\ze;')
    endif
  endfor
  return ''
endfunction "}}}

fun! s:create_fluent_builder() "{{{
  let l:indent = &et ? '    ' : '	'
  let dirs = s:calculate_dirs()
  exe 'lcd ' . dirs.project_dir
  let l:props = s:get_property_lines()
  call map(l:props, '<SID>clean_property(v:val)')
  let l:class_name = expand('%:t:r') . 'Builder'
  if filereadable(expand('%:p:h').'/'.l:class_name)
    echohl warningmsg | echo l:class_name . '  already exists' | echohl none
    return
  endif
  let l:imports = s:find_imports(s:extract_types_from_props(l:props))

  let l:cur_package = matchstr(s:current_clazz(), '\v^.+\ze\.\w+$')

  let l:lines = ['package ' . l:cur_package . ';', '']
  let l:lines += l:imports
  let l:lines += ['', 'public class ' . l:class_name . ' {', '']
  let l:lines += map(copy(l:props), 'l:indent . ''private '' . v:val . '';''')
  call add(l:lines, '')
  let l:lines += s:define_with_methods(l:props, l:class_name, l:indent)
  let l:lines += s:define_build_method(l:props, l:indent)
  call add(l:lines, '}')
  let l:set = '/'
  if has('win32')
    let l:sep = '\'
  endif

  let l:f=expand('%:p:h').l:sep.l:class_name.'.java'
  call writefile(l:lines, l:f)
  exe "lcd " . dirs.cwd_dir
  exe "e " . l:f
endfunction "}}}

fun! s:define_with_methods(props, class, indent) "{{{
  let l:lines = []
  for l:prop in a:props
    let l:lines +=
          \ split(substitute(l:prop, '\v^(.+) (\w+)$',
          \ a:indent . 'public ' . a:class . ' with\u\2(\1 \2) {@' .
          \ repeat(a:indent, 2) . 'this.\2 = \2;@' .
          \ repeat(a:indent, 2) . 'return this;@' .
          \ a:indent . '}@@', ''), '\v\@')
  endfor
  return l:lines
endfunction "}}}

fun! s:define_build_method(props, indent) "{{{
  let l:type = expand('%:t:r')
  let l:var = substitute(l:type, '^.', '\l&', '')
  let l:lines = []
  call add(l:lines, a:indent . 'public ' . l:type . ' build() {')
  call add(l:lines, repeat(a:indent, 2) . l:type . ' ' .
        \ l:var . ' = new ' . l:type . '();')
  for l:prop in a:props
    call add(l:lines,
      \ substitute(l:prop, '\v^(.+) (\w+)$',
      \ repeat(a:indent, 2) . l:var . '.set\u\2(\2);', ''))
  endfor
  call add(l:lines, repeat(a:indent, 2) . 'return ' . l:var . ';')
  call add(l:lines, a:indent . '}')
  return l:lines
endfunction "}}}

fun! s:find_imports(props) "{{{
  let l:types=map(copy(a:props), 'matchstr(v:val, ''\v^\w+\ze'')')
  let l:imports=[]
  let l:imported=[]
  for l:type in l:types
    if index(l:imported, l:type) > 0
      continue
    endif
    let l:line_import = searchpos('\v^import .+\.<' . l:type . '>;', 'bn')[0]
    if l:line_import > 1
      let l:import=getline(l:line_import)
      call add(l:imported, l:type)
      call add(l:imports, l:import)
    endif
  endfor
  return l:imports
endfunction "}}}

fun! VimJMessSID() "{{{
  return s:sid
endfunction "}}}

fun! s:setup_javavimmess() "{{{
  inoremap <expr> <C-g><C-e> <SID>autowrite_type_var()
  inoremap <expr> <C-g>e     <SID>autowrite_type_var()
  inoremap <expr> <C-g>E     <SID>autowrite_new_from_var()
  nnoremap g5 :call CreateDescribeWindow()<CR>

  command! -buffer GetSet call s:getters_setters()
  command! -buffer ToString call s:gen_tostring()
  command! -buffer HashCode call s:gen_hashcode()
  command! -buffer Equalsj call s:gen_equals()
  command! -buffer CompileOnSaveToggle call ToggleSettingCompileOnSave()
  command! -buffer CacheCurrProjMaven call s:cacheThisMavenProj()
  command! -buffer CreateIndex call s:cacheThisMavenProj() | call s:list_classes_cache()
  command! -buffer IndexCache call s:list_classes_cache()
  command! -bar -buffer Javac call JavacBuffer()
  command! -bar -buffer Junit call JUnitCurrent()
  command! -bar -buffer Javap call Javapcword()
  command! -buffer A call s:Alternate()
  command! SerialVer call s:serial_ver()
  command! Updatesnapshots call s:update_jar_snapshots()
  command! Upsnapshots call s:update_jar_snapshots()
  command! FluentBuilder call s:create_fluent_builder()

  nnoremap <silent><buffer> gG :GetSet<cr>
  nnoremap <silent><buffer> gS :ToString<cr>
  nnoremap <silent><buffer> gH :HashCode<cr>
  nnoremap <silent><buffer> gQ :Equalsj<cr>
  nnoremap <silent><buffer> g7 :call <SID>javap_current()<cr>
  inoremap <silent><buffer> <C-g><C-i> <Esc>:call CreateAutoImportWindow(1)<cr>
  inoremap <silent><buffer> <C-g>i <Esc>:call CreateAutoImportWindow(1)<cr>
  nnoremap <silent><buffer> <C-g><C-i> :call CreateAutoImportWindow(0)<cr>
  nnoremap <silent><buffer> <C-g>p :call CreateAutoImportWindow(0)<cr>
  inoremap <silent><buffer> <expr> <C-g><C-n> <SID>prepare_completion()
endfunction "}}}

call s:setup_javavimmess()
