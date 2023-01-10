# ztags

ztags for [tagbar](https://github.com/preservim/tagbar)



## How to build

```sh
$ zig build -Drelease-safe
```



## How to use

Add `ztags` to your `PATH` and put the following configuration to your `.vimrc`.

```vim-script
let g:tagbar_type_zig = {
    \ 'ctagstype': 'zig',
    \ 'kinds' : [
        \'const:constant',
        \'var:variable',
        \'field:field',
        \'enum:enum:1',
        \'union:union:1',
        \'struct:struct:1',
        \'function:function',
        \'test:test',
    \ ],
    \ 'sro' : '.',
    \ 'kind2scope' : {
        \ 'enum' : 'enum',
        \ 'union' : 'union',
        \ 'struct' : 'struct',
    \ },
    \ 'ctagsbin' : 'ztags',
    \ 'ctagsargs' : ''
\ }
```
