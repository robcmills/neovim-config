let SessionLoad = 1
let s:so_save = &g:so | let s:siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1
let v:this_session=expand("<sfile>:p")
silent only
silent tabonly
cd ~/src/openspace/web/icedemon
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
let s:shortmess_save = &shortmess
if &shortmess =~ 'A'
  set shortmess=aoOA
else
  set shortmess=aoO
endif
badd +566 term://~/src/openspace/web/icedemon//43185:/opt/homebrew/bin/bash
badd +2 config/local/BuildDev.js
badd +902 src/js/openapi/spec.json
badd +44 src/js/openapi/openapi.ts
badd +13 src/js/api/capture/getCaptureVionav.ts
badd +75 src/js/icedemon/navigation/ElevatedPanosController.ts
badd +7 src/js/query/hooks/capture/passiveCapture/usePassiveCaptureQuery.ts
badd +11 src/js/api/capture/getElevatedPanos.ts
badd +24 src/js/openapi/generated/models/Includes.ts
badd +1 src/js/api/capture/types/CaptureVionavResponse.ts
argglobal
%argdel
$argadd .
tabnew +setlocal\ bufhidden=wipe
tabrewind
edit src/js/openapi/openapi.ts
argglobal
balt src/js/openapi/spec.json
setlocal fdm=indent
setlocal fde=0
setlocal fmr={{{,}}}
setlocal fdi=#
setlocal fdl=99
setlocal fml=1
setlocal fdn=20
setlocal fen
33
normal! zo
let s:l = 44 - ((42 * winheight(0) + 26) / 52)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 44
normal! 0
lcd ~/src/openspace/web/icedemon
tabnext
edit diffview://null
let s:save_splitbelow = &splitbelow
let s:save_splitright = &splitright
set splitbelow splitright
wincmd _ | wincmd |
vsplit
wincmd _ | wincmd |
vsplit
2wincmd h
wincmd w
wincmd w
let &splitbelow = s:save_splitbelow
let &splitright = s:save_splitright
wincmd t
let s:save_winminheight = &winminheight
let s:save_winminwidth = &winminwidth
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
exe '1resize ' . ((&lines * 51 + 27) / 55)
exe 'vert 1resize ' . ((&columns * 41 + 90) / 181)
exe '2resize ' . ((&lines * 51 + 27) / 55)
exe 'vert 2resize ' . ((&columns * 76 + 90) / 181)
exe '3resize ' . ((&lines * 51 + 27) / 55)
exe 'vert 3resize ' . ((&columns * 83 + 90) / 181)
argglobal
enew
file diffview:///panels/4/DiffviewFilePanel
balt ~/src/openspace/web/icedemon/src/js/api/capture/getCaptureVionav.ts
setlocal fdm=manual
setlocal fde=0
setlocal fmr={{{,}}}
setlocal fdi=#
setlocal fdl=99
setlocal fml=1
setlocal fdn=20
setlocal nofen
lcd ~/src/openspace/web/icedemon
wincmd w
argglobal
balt ~/src/openspace/web/icedemon/src/js/api/capture/getCaptureVionav.ts
setlocal fdm=diff
setlocal fde=0
setlocal fmr={{{,}}}
setlocal fdi=#
setlocal fdl=0
setlocal fml=1
setlocal fdn=20
setlocal fen
let s:l = 1 - ((0 * winheight(0) + 25) / 50)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 1
normal! 0
lcd ~/src/openspace/web/icedemon
wincmd w
argglobal
if bufexists(fnamemodify("~/src/openspace/web/icedemon/src/js/api/capture/getCaptureVionav.ts", ":p")) | buffer ~/src/openspace/web/icedemon/src/js/api/capture/getCaptureVionav.ts | else | edit ~/src/openspace/web/icedemon/src/js/api/capture/getCaptureVionav.ts | endif
if &buftype ==# 'terminal'
  silent file ~/src/openspace/web/icedemon/src/js/api/capture/getCaptureVionav.ts
endif
setlocal fdm=diff
setlocal fde=0
setlocal fmr={{{,}}}
setlocal fdi=#
setlocal fdl=0
setlocal fml=1
setlocal fdn=20
setlocal fen
let s:l = 1 - ((0 * winheight(0) + 25) / 50)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 1
normal! 0
lcd ~/src/openspace/web/icedemon
wincmd w
exe '1resize ' . ((&lines * 51 + 27) / 55)
exe 'vert 1resize ' . ((&columns * 41 + 90) / 181)
exe '2resize ' . ((&lines * 51 + 27) / 55)
exe 'vert 2resize ' . ((&columns * 76 + 90) / 181)
exe '3resize ' . ((&lines * 51 + 27) / 55)
exe 'vert 3resize ' . ((&columns * 83 + 90) / 181)
tabnext 1
if exists('s:wipebuf') && len(win_findbuf(s:wipebuf)) == 0 && getbufvar(s:wipebuf, '&buftype') isnot# 'terminal'
  silent exe 'bwipe ' . s:wipebuf
endif
unlet! s:wipebuf
set winheight=1 winwidth=20
let &shortmess = s:shortmess_save
let &winminheight = s:save_winminheight
let &winminwidth = s:save_winminwidth
let s:sx = expand("<sfile>:p:r")."x.vim"
if filereadable(s:sx)
  exe "source " . fnameescape(s:sx)
endif
let &g:so = s:so_save | let &g:siso = s:siso_save
set hlsearch
doautoall SessionLoadPost
unlet SessionLoad
" vim: set ft=vim :
