# ztags

ztags for [tagbar](https://github.com/preservim/tagbar)



## How to build

```sh
$ zig build -Doptimize=ReleaseSafe
```



## How to use

Add `ztags` to your `PATH` and put the following configuration to your `.vimrc`.

```vim-script
let g:tagbar_type_zig = {
    \ 'ctagstype': 'zig',
    \ 'kinds' : [
        \'import:imports',
        \'const:constants',
        \'var:variables',
        \'field:fields',
        \'error:errors',
        \'enum:enum:1',
        \'union:union:1',
        \'struct:struct:1',
        \'opaque:opaque:1',
        \'function:functions',
        \'comptime:comptimes',
        \'test:tests',
    \ ],
    \ 'sro' : '.',
    \ 'kind2scope' : {
        \ 'enum' : 'enum',
        \ 'union' : 'union',
        \ 'struct' : 'struct',
        \ 'opaque' : 'opaque',
    \ },
    \ 'ctagsbin' : 'ztags',
    \ 'ctagsargs' : ''
\ }
```
