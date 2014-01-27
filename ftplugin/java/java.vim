let s:javac_core_command = 'javac -cp .cache/*:target/classes -g:lines,vars,source -sourcepath src/main/java -d target/classes'
let s:javac_test_command = 'javac -cp .cache/*:target/classes:target/test-classes -g:lines,vars,source -sourcepath src/main/java:src/test/java -d target/test-classes'
let s:junit_exec = 'java -cp .cache/*:target/classes:target/test-classes org.junit.runner.JUnitCore'

fun! CacheThisMavenProj() "{{{
  let adir = matchstr(findfile('pom.xml', '.;'), '\v.+\zepom\.xml$')
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

fun! s:populate_cache(a_dir) "{{{
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
  let line = filter(lines, 'v:val =~ ''\vjar[;:]''')[0]
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
  "I think slicing is much more effective
  "Hope find time to test the teory
  for i in range(len_of_files)
    call add(files_to_copy, a:files[i])
    if len(files_to_copy) % 25 == 0
      call s:exec_copy_command_win32(files_to_copy)
      let files_to_copy = []
      redraw | echo i + 1 . ' of ' . len_of_files
    endif
  endfor
  call  s:exec_copy_command_win32(files_to_copy)
  redraw | echo 'DONE'
endfunction "}}}

fun! s:exec_copies(files) "{{{
  let files = map(copy(a:files), 'fnameescape(v:val)')
  let cmdstr = 'cp ' . join(files, ' ') . ' .cache'
  call system(cmdstr)
  redraw | echo 'DONE'
endfunction "}}}

fun! s:exec_copy_command_win32(files) "{{{
  let cmdstr = ''
  for path in a:files
    let cmdstr .= 'copy ' . fnameescape(path) . ' .cache && '
  endfor
  let cmdstr = substitute(cmdstr, '\v&&\s*$', '', '') . ' .cache'
  call system(cmdstr)
endfunction "}}}

fun! s:calculate_dirs() "{{{
  let project_dir = fnameescape(matchstr(findfile('pom.xml', '.;'), '\v.+\zepom\.xml$'))
  let vim_dir = fnameescape(getcwd())
  return {'project_dir': project_dir, 'vim_dir': vim_dir}
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
  if expand('%:t') =~ 'Test'
    let javac = s:javac_test_command
  endif
  try
    execute 'lcd ' . dirs.project_dir
    call s:createclassesdirs()
    let output = system(javac . ' ' . expand('%'))
    redraw
    if output == ''
      echom 'OK'
    else
      let lines = split(output, '\v\n')
      for l in lines
        echom l
      endfor
    endif
  catch /.*/
  finally
    execute 'lcd ' . dirs.vim_dir
  endtry
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

let b:compile_on_save = 0

augroup command_on_save
  au!
  au BufWritePost *.java call CompileOnSave()
augroup END

command! CompileOnSaveToggle call ToggleSettingCompileOnSave()
command! CacheCurrProjMaven call CacheThisMavenProj()
command! JavaC call JavaCBuffer()

