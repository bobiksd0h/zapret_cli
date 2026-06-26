# cfgs

Стратегии (конфигурации), хостлисты и fake-пейлоады для запрета на движке
**nfqws2** ([bol-van/zapret2](https://github.com/bol-van/zapret2)).

Это порт стратегий, написанных под первую версию запрета, на новый движок **nfqws2**.
В нём стратегии больше не «зашиты» в C-опции `--dpi-desync-*`, а описываются как профили
с вызовами Lua-функций десинхронизации (`--lua-desync=<функция>:арг=знач:...`).
См. `docs/manual.en.md` в репозитории движка.

## Структура

```
configurations/   готовые стратегии (полные файлы config для zapret2)
lists/            хостлисты и ipset-листы (формат не изменился, перенесены как есть)
bin/              бинарные fake-пейлоады (TLS ClientHello / QUIC Initial)
```

Файлы `bin/` устанавливаются в `/opt/zapret2/files/fake/` и подключаются в стратегиях
как именованные blob'ы: `--blob=имя:@/opt/zapret2/files/fake/файл.bin`, затем
`--lua-desync=fake:blob=имя`. Встроенные blob'ы zapret2 (`fake_default_tls`,
`fake_default_http`, `fake_default_quic`) доступны без объявления.

## Соответствие опций zapret1 → zapret2 (nfqws2)

| zapret1 | zapret2 (nfqws2) |
| :-- | :-- |
| `--new` / разделитель профилей | `--new` |
| `--filter-tcp` / `--filter-udp` / `--filter-l7` | без изменений |
| `--hostlist=… --hostlist-exclude=…` (+ `MODE_FILTER=autohostlist`) | плейсхолдеры `<HOSTLIST>` / `<HOSTLIST_NOAUTO>` |
| `--hostlist-domains=` / `--ipset=` | без изменений |
| `--dpi-desync=fake --dpi-desync-fake-tls=F` | `--payload=tls_client_hello --lua-desync=fake:blob=<F>` |
| `--dpi-desync=fake --dpi-desync-fake-quic=F` | `--payload=quic_initial --lua-desync=fake:blob=<F>` |
| `--dpi-desync-fake-discord/stun=F` (`--filter-l7=discord,stun`) | `--payload=discord_ip_discovery,stun --lua-desync=fake:blob=<F>` |
| `--dpi-desync-any-protocol` (+ `--dpi-desync-fake-unknown-udp=F`) | `--payload=all --lua-desync=fake:blob=<F>` |
| `--dpi-desync-repeats=N` | `:repeats=N` |
| `--dpi-desync-fooling=md5sig` | `:tcp_md5` |
| `--dpi-desync-fooling=badseq` | `:tcp_seq=-10000` |
| `--dpi-desync-fooling=ts` | `:tcp_ts=-1000` |
| `--dpi-desync-autottl=N` | `:ip4_autottl=-N,3-20` |
| `--ip-id=zero` | `:ip_id=zero` |
| `--dpi-desync-cutoff=nX` / `dX` | `--out-range=-nX` / `--out-range=-dX` |
| `--dpi-desync=multisplit --dpi-desync-split-pos=P` | `--lua-desync=multisplit:pos=P` |
| `--dpi-desync-split-seqovl=N --dpi-desync-split-seqovl-pattern=F` | `:seqovl=N:seqovl_pattern=<F>` |
| `--dpi-desync=multidisorder` | `--lua-desync=multidisorder:pos=…` |
| `--dpi-desync=split` / `split2` | `--lua-desync=multisplit:pos=1,midsld` / `pos=method+2` |
| `--dpi-desync=disorder2` | `--lua-desync=multidisorder:pos=1,midsld` |
| `--dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=H` | `--lua-desync=hostfakesplit:host=H` |
| `…hostfakesplit-mod=…,altorder=1` | `hostfakesplit:…:disorder_after:` |
| `--dpi-desync-fake-tls-mod=rnd,dupsid,sni=X` | `:tls_mod=rnd,dupsid,sni=X` |
| `--dpi-desync-udplen-increment=N --dpi-desync-udplen-pattern=0xHEX` | `--lua-desync=udplen:increment=N:pattern=0xHEX` |

> Движки nfqws1 и nfqws2 отличаются по внутренней реализации, поэтому стратегии
> переписаны по смыслу и методике обхода, а не байт-в-байт. Параметры подобраны по
> официальным шаблонам `blockcheck2.d/standard` из zapret2.

## Доступные стратегии

Перенесены **ВСЕ 53 стратегии** из `zapret.cfgs` (`general`, `general_ALT…`,
`GeneralFix…`, `DiscordFix…`, `UltimateFix…`, `general_МГТС…`, `RussiaFix`,
`preset_russia`, `YoutubeFix_ALT`, `fix_v1…v3`, `general_simple_fake…` и т.д.) плюс
`conf-custom` — чистый редактируемый шаблон. Итого 54 файла в `configurations/`.

Каждый файл — это полная конфигурация zapret2; стратегия задана в `NFQWS2_OPT`.
Имена и назначение сохранены 1:1 с первой версией, чтобы было привычно выбирать в меню.

### Как переносились

Перенос выполнен механически по таблице соответствия выше (профили `--new`,
методы `--dpi-desync=…` → `--lua-desync=…`, fooling/autottl/cutoff/seqovl/blob и т.д.).
Подстановки хостлистов сделаны через `<HOSTLIST>` / `<HOSTLIST_NOAUTO>`; профили с
`--ipset`/`--hostlist-domains` получают только список исключений, без общего include-листа.

> Все 54 конфигурации проверены прогоном через реальный бинарник `nfqws2`
> (`--intercept=0` — выполняет инициализацию Lua, загрузку blob'ов и регистрацию
> хостлистов без захвата трафика): 54/54 инициализируются без ошибок парсинга/Lua.
> Это проверка корректности синтаксиса, а не гарантия обхода DPI у конкретного провайдера —
> эффективность по-прежнему зависит от сети (используйте автоподбор стратегии в меню).

Движки nfqws1 и nfqws2 отличаются по внутренней реализации, поэтому стратегии
переписаны по смыслу и методике обхода, а не байт-в-байт.
