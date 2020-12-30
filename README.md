# stringtime

Zig library for string templating. 

## Quick Example
```
Hi {{name}} at index #{{index}}
```

```
{{ for(0..11) |index| }}
Hello World {{index}}!
{{ end }}
```

```
{{ foreach(list) |item| }}
Print {{item}}
{{ end }}
```

## Install

This project assume current Zig master (0.7.0+a1fb10b76).

```
zig build test
```

## Language reference
