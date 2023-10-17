---
title: "OpenSSL::Cipher.new(”bf-ecb”)を追う"
slug: "openssl-cipher-code-reading"
date: 2023-10-17T23:30:00+09:00
draft: false
---
{{< toc >}}

## これは何？
この記事は、OpenSSLのBlowfish実装回りのコードを追いながらNotionに書き残していたメモを、当サイト用にエクスポートして体裁を整えたものです。一応[Notionのメモをそのままpublishしたもの](https://osak.notion.site/OpenSSL-Cipher-new-bf-ecb-f96522bf1dae4b349d7fbf2478018072)もあるけど、これは実体がNotion側にあることもあって永続性が不安なので、エクスポートしたものを当サイトの一部として配信するという手法を取っています。こっちのバージョンはシンタックスハイライトを付けられていないので、先のリンクが生きている間はそっちを読んだほうが読みやすいと思います。

ソースコードやシステムを解析するときの試行錯誤ログのような記事を読むのが好きなので、せっかくだし自分がやったことも公開しておくと誰かが喜ぶんじゃないかなと思い、公開することにしました。OpenSSLについて何かを解説したり、ソースコードの歩き方の教本にしたりする意図は特にありませんが、読み方は読み手の自由なので好きなように読んでください。

### 背景
mikutterはOAuthの認証トークンを設定ファイルに保存する際、[平文が見えると気持ち悪いからという理由で難読化をかけている](https://dev.mikutter.hachune.net/issues/1585#note-6)。この難読化のためにOpenSSLの提供するBlowfishアルゴリズムを使って暗号化をしていたが、OpenSSL 3.xではこのアルゴリズムがdeprecatedとなり、普通にはロードできなくなってしまった。API的には設定で回避できるものの、Rubyの`openssl` gemは執筆時点でこのAPIを使えるようにできていなかったため、mikutterはOpenSSL 3.x環境で（よっぽど運が良くない限り）起動しなくなってしまった。

……という問題が1年以上前に持ち上がり、仮対応が入ったものの根本的な解決には至っていなかった。先日梅田でてオフ（mikutter界隈のオフ会をこう呼ぶことがあります）をしたときにもこの話が出て、OpenSSLのコードは読みにくくてヤバいという話でちょっと盛り上がったことがあったり、その後[@tsutsuii](https://social.mikutter.hachune.net/@tsutsuii)さんにBlowfish対応やってと圧をかけられたりしたという背景から、試しにOpenSSLのBlowfish回りの実装を読んでみることにした。

<!--more-->

## 問題

OpenSSL 3.xではBlowfishという暗号アルゴリズムがdeprecatedされ、デフォルトではロードできなくなった。mikutterはBlowfishでsecretを暗号化しているためそういう環境で死ぬ。

[バグ #1585: OpenSSL 3.x 環境 (ubuntu 22.04 等) で mikutter が起動しない - mikutter - やること](https://dev.mikutter.hachune.net/issues/1585)

deprecatedなものをビルドしないというオプションを明示的に指定しない限り、Blowfishもlegacy providerとしてロードすることはできる。しかし現状のRubyはlegacy providerをサポートしていない。ちょっと待てばlegacy providerサポートが入りはする。

[https://github.com/ruby/openssl/pull/635](https://github.com/ruby/openssl/pull/635)

とはいえ時間がかかるし、legacy providerなしでOpenSSLをビルドしているような環境でどうなん？という問題もある。一回マイグレーションさえすればもっとロバストな暗号化アルゴリズムに変換できるので、自力でdecryptを再実装したい。

## 調査

### mikutterの実装

mikutterは `Plugin::World::Keep` で以下のようにしてsecretを暗号化している。

```ruby
  def encrypt(str)
      cipher = OpenSSL::Cipher.new('bf-ecb').encrypt
      cipher.key_len = ACCOUNT_CRYPT_KEY_LEN
      cipher.key = key
      cipher.update(str) << cipher.final end
```

[/plugin/world/keep.rb - mikutter - やること](https://dev.mikutter.hachune.net/projects/mikutter/repository/main/revisions/master/entry/plugin/world/keep.rb#L125)

`OpenSSL::Cipher` はRubyにバンドルされている。

ドキュメント：

[class OpenSSL::Cipher (Ruby 3.2 リファレンスマニュアル)](https://docs.ruby-lang.org/ja/latest/class/OpenSSL=3a=3aCipher.html)

実装：

[https://github.com/ruby/openssl](https://github.com/ruby/openssl)

### OpenSSL側の実装

OpenSSLの気持ちは全然知らないので、とりあえず雰囲気を掴むためにOpenSSLでBlowfishがどういう実装をされているか見てみる。

[https://github.com/openssl/openssl](https://github.com/openssl/openssl)

トップレベルを眺めていると `crypto` というディレクトリがあるので見てみると、いかにも暗号アルゴリズムの実装が列挙されていそうな感じになっている。眺めると `bf` というディレクトリがあり、Blowfishっぽさがある。

ファイル名を眺めて `bf_enc.c` というのが何らかのエントリポイントっぽい名前なので見てみる。コメントに “Blowfish as implemented from ‘…’” とあるのでこれがBlowfishであるという予想は正解っぽい。
([link](https://github.com/openssl/openssl/blob/831602922f19a8f39d0c0fae425b81e9ab402c69/crypto/bf/bf_enc.c#L20))

`BF_encrypt` はなんか固定長の鍵でWord単位の暗号化っぽいことをやってるように見える。コメントが全然ないが、public interfaceっぽい雰囲気の関数名なのでぐぐってみるとmanがヒットする。

[/docs/man1.0.2/man3/blowfish.html](https://www.openssl.org/docs/man1.0.2/man3/blowfish.html)

これを読むと以下のことが分かる。

- BlowfishというのはBlock cipherの一種であり、64ビットのデータを暗号化するアルゴリズムである。
- `BF_encrypt` は lowest level functions for Blowfish encryptionで、上位レベルの関数から呼ばれる。実際さっきのリポジトリの他のファイルを見ると、 `BF_ecb_encrypt` とか `BF_ofb64_encrypt` のような何らかのカテゴリに属すっぽい関数から呼ばれている。
- `BF_ecb_encrypt` は入力の先頭64ビットを暗号化する。
- `BF_cbc_encrypt` 等は可変長のデータに対応している。
- CBCはCipher Block Chainingの略。よくわからんが複数の鍵をscheduleとして指定すると、それらを順番に使ってくれるっぽい。

ECBというのが何なのか結局よく分からんので “block cipher ECB” でぐぐるとWikipediaが出てきて、Electronic codebookの略だということが分かる。

[Block cipher mode of operation](https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation#Electronic_codebook_(ECB))

前後のデータに関係なく、同じデータを暗号化した結果が必ず同じになるため、ある種の暗号表のようなものだというニュアンスらしい。

### OpenSSL::Cipherの実装

Blowfishの公開する関数は何種類かあるし、64ビットの暗号化を繰り返し掛けるという実装も可能なので、Ruby側で実際にどうやって暗号化しているのかを知る必要がある。本体の大半はC extensionにあるようなので、暗号化ロジックの本体っぽい `Ciper#update` がどうなっているかを調べたい。ファイル一覧を見ると `ossl_cipher.c` というのがあるので開き、関数を眺めると `ossl_cipher_update` というのがある。RDocも付いているしこれでよさそう（良い子はちゃんと `rb_define_method` を追いましょう）。
([link](https://github.com/ruby/openssl/blob/6b3dd6a372c5eabc88bf35a312937ee3e1a6a105/ext/openssl/ossl_cipher.c#L373))

Rubyコード側で1 wordずつ暗号化してたりするかと思いきや、引数のバリデーションをしてから `ossl_cipher_update_long` という関数を呼び出して、その中で `EVP_CipherUpdate` を呼んでいる。 `in_len` を見ると `INT_MAX/2 + 1` バイトをいっぺんに処理してるのでこれは実質無限。命名規則的にこれはOpenSSLの関数っぽい。

### EVPの実装

さっきのmanの最後の方を見ると `EVP_EncryptInit(3)` へのリンクが張られているので見てみる。

[/docs/man1.0.2/man3/EVP_EncryptInit.html](https://www.openssl.org/docs/man1.0.2/man3/EVP_EncryptInit.html)

EVPが何の略かはよく分からんが、とりあえず高レベルのインターフェースではあるらしい。確かに初期化時に文字列で `"bf-ecb"` とか渡してるしそういう抽象化はまあ当然あるよね。OpenSSLのリポジトリを `EVP_CipherUpdate` で検索すると `crypto/evp/evp_enc.c` にあることがわかる。
([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/crypto/evp/evp_enc.c#L429))

暗号化の本体は `EVP_EncryptUpdate` らしいので中を見てみると、本体は `ctx->cipher->cupdate` らしいことがわかる。Cでポリモーフィズムするいつものやつですね。 `ctx` は引数で `EVP_CIPHER_CTX *ctx` と宣言されているので、GitHubのdefinition searchをポチポチすると以下のことがわかる。

- `EVP_CIPHER_CTX` の実体は `evp_cipher_ctx_st` にある。 `ctx->cipher` は `const EVP_CIPHER *cipher` と宣言されている。
([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/crypto/evp/evp_local.h#L36))

- `EVP_CIPHER` の実体は `evp_cipher_st` で、 `ctx->cipher->cupdate` というのは `OSSL_FUNC_cipher_update_fn *cupdate` と宣言されている。
([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/include/crypto/evp.h#L297))

見た目的にもそれぞれの暗号化アルゴリズムに対応して `EVP_CIPHER` が定義されていそう。しかしさっき見た `crypto/bf` にはそれっぽい定義はなかった。じゃあどこで作ってるんだ？

とりあえずどこかで下位の `BF_encrypt` や `BF_ecb_encrypt` を参照するはずなのでGitHubで検索をかけてみるも、さっきの `crypto/bf` とドキュメントしかヒットしないので、どうもマクロでごにょごにょしているっぽい雰囲気がある。

さっきの `evp_cipher_st` 内の `cupdate` をクリックするとReference searchが出るので全部見てみる。すると `crypto/evp/evp_enc.c` の中でこのフィールドに代入しているのが分かるので見てみる（ちなみにこれは単に `cupdate` でcode searchしてもなぜか出てこない）。するといかにもコンストラクタっぽい関数になっている。

[link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/crypto/evp/evp_enc.c#L1582)

`OSSL_FUNC_cipher_update` でcode searchすると、関数定義は見つからないが `OSSL_FUNC_CIPHER_UPDATE` という定数と対応する関数がペアにされているロジックがたくさん出てくる。よく分からんが `OSSL_DISPATCH` という型の構造体からいい感じに対応する関数を拾ってきてるっぽい。パスを見るとProviderの実体が `providers/implementations/ciphers` の中にあるっぽいことが分かるので、見てみると `cipher_blowfish.{c,h}` と `ciper_blowfish_hw.c` というファイルがある。HWが何の略かは分からないけど、バインディングに関連する概念っぽさがある。

[link](https://github.com/openssl/openssl/blob/master/providers/implementations/ciphers/cipher_blowfish.h)

### Blowfish Providerの実装

次の目標として、Blowfishに対応する `OSSL_DISPATCH` がどこで宣言されているかを見つけたい。今見つけたコードは短いものの、こういうコードにありがちなパターンでマクロで宣言が抽象化されている。頑張って読むと以下の構造になっていることが分かる。

```c
//// Blowfish cipherのdescriptor（？）を生成して返すやつ。実装はマクロで生成されている。
//// HWがなんの略かは謎。
//// cipher_blowfish.h
const PROV_CIPHER_HW *ossl_prov_cipher_hw_blowfish_ecb(size_t keybits);

//// 実装を生成するマクロの呼び出し
//// cipher_blowfish_hw.c
PROV_CIPHER_HW_blowfish_mode(ecb, ECB)

//// 上記マクロの定義（同ファイル）
# define PROV_CIPHER_HW_blowfish_mode(mode, UCMODE)                            \
IMPLEMENT_CIPHER_HW_##UCMODE(mode, blowfish, PROV_BLOWFISH_CTX, BF_KEY,        \
                             BF_##mode)                                        \
static const PROV_CIPHER_HW bf_##mode = {                                      \
    cipher_hw_blowfish_initkey,                                                \
    cipher_hw_blowfish_##mode##_cipher                                         \
};                                                                             \
const PROV_CIPHER_HW *ossl_prov_cipher_hw_blowfish_##mode(size_t keybits)      \
{                                                                              \
    return &bf_##mode;                                                         \
}

//// 上記マクロから呼ばれている IMPLEMENT_CIPHER_HW_ECB の実装
//// providers/implementations/include/prov/ciphercommon.h
# define IMPLEMENT_CIPHER_HW_ECB(MODE, NAME, CTX_NAME, KEY_NAME, FUNC_PREFIX)   \
static int cipher_hw_##NAME##_##MODE##_cipher(PROV_CIPHER_CTX *ctx,            \
                                         unsigned char *out,                   \
                                         const unsigned char *in, size_t len)  \
{                                                                              \
    size_t i, bl = ctx->blocksize;                                             \
    KEY_NAME *key = &(((CTX_NAME *)ctx)->ks.ks);                               \
                                                                               \
    if (len < bl)                                                              \
        return 1;                                                              \
    for (i = 0, len -= bl; i <= len; i += bl)                                  \
        FUNC_PREFIX##_encrypt(in + i, out + i, key, ctx->enc);                 \
    return 1;                                                                  \
}
```

これでとりあえず、`BF_ecb_encrypt` を逐次的に呼ぶ関数が `cipher_hw_blowfish_ecb_cipher` という名前で存在していることが分かる。 `ctx->blocksize` が8でないと壊れるけど、たぶんどっかでバリデーションされてるんでしょう……。また、この関数を含む `PROV_CIPHER_HW` という型のdescriptorっぽい構造体が `ossl_prov_cipher_hw_blowfish_ecb` という関数を通して公開されている。

じゃあこの `ossl_prov_cipher_hw_blowfish_ecb` はどこから呼ばれてるのか？まだ追ってないマクロ呼び出しが `cipher_blowfish.c` に書いてある（が、明示的にはexportされてなさそうに見える）ので追ってみる。

```c
//// cipher_blowfish.c
IMPLEMENT_var_keylen_cipher(blowfish, BLOWFISH, ecb, ECB, BF_FLAGS, 128, 64, 0, block)

//// Reference Searchすると出てくるマクロの実装
//// providers/implementations/include/prov/ciphercommon.h
# define IMPLEMENT_var_keylen_cipher(alg, UCALG, lcmode, UCMODE, flags, kbits,  \
                                    blkbits, ivbits, typ)                      \
IMPLEMENT_generic_cipher_genfn(alg, UCALG, lcmode, UCMODE, flags, kbits,       \
                               blkbits, ivbits, typ)                           \
IMPLEMENT_var_keylen_cipher_func(alg, UCALG, lcmode, UCMODE, flags, kbits,     \
                                 blkbits, ivbits, typ)

//// さらにその実装（同じファイルにある）

# define IMPLEMENT_generic_cipher_genfn(alg, UCALG, lcmode, UCMODE, flags,      \
                                       kbits, blkbits, ivbits, typ)            \
static OSSL_FUNC_cipher_get_params_fn alg##_##kbits##_##lcmode##_get_params;   \
static int alg##_##kbits##_##lcmode##_get_params(OSSL_PARAM params[])          \
{                                                                              \
    return ossl_cipher_generic_get_params(params, EVP_CIPH_##UCMODE##_MODE,    \
                                          flags, kbits, blkbits, ivbits);      \
}                                                                              \
static OSSL_FUNC_cipher_newctx_fn alg##_##kbits##_##lcmode##_newctx;           \
static void * alg##_##kbits##_##lcmode##_newctx(void *provctx)                 \
{                                                                              \
     PROV_##UCALG##_CTX *ctx = ossl_prov_is_running() ? OPENSSL_zalloc(sizeof(*ctx))\
                                                     : NULL;                   \
     if (ctx != NULL) {                                                        \
         ossl_cipher_generic_initkey(ctx, kbits, blkbits, ivbits,              \
                                     EVP_CIPH_##UCMODE##_MODE, flags,          \
                                     ossl_prov_cipher_hw_##alg##_##lcmode(kbits),\
                                     provctx);                                 \
     }                                                                         \
     return ctx;                                                               \
}

# define IMPLEMENT_var_keylen_cipher_func(alg, UCALG, lcmode, UCMODE, flags,    \
                                         kbits, blkbits, ivbits, typ)          \
const OSSL_DISPATCH ossl_##alg##kbits##lcmode##_functions[] = {                \
    { OSSL_FUNC_CIPHER_NEWCTX,                                                 \
      (void (*)(void)) alg##_##kbits##_##lcmode##_newctx },                    \
    { OSSL_FUNC_CIPHER_FREECTX, (void (*)(void)) alg##_freectx },              \
    { OSSL_FUNC_CIPHER_DUPCTX, (void (*)(void)) alg##_dupctx },                \
    { OSSL_FUNC_CIPHER_ENCRYPT_INIT, (void (*)(void))ossl_cipher_generic_einit },\
    { OSSL_FUNC_CIPHER_DECRYPT_INIT, (void (*)(void))ossl_cipher_generic_dinit },\
    { OSSL_FUNC_CIPHER_UPDATE, (void (*)(void))ossl_cipher_generic_##typ##_update },\
    { OSSL_FUNC_CIPHER_FINAL, (void (*)(void))ossl_cipher_generic_##typ##_final },  \
    { OSSL_FUNC_CIPHER_CIPHER, (void (*)(void))ossl_cipher_generic_cipher },   \
    { OSSL_FUNC_CIPHER_GET_PARAMS,                                             \
      (void (*)(void)) alg##_##kbits##_##lcmode##_get_params },                \
    { OSSL_FUNC_CIPHER_GET_CTX_PARAMS,                                         \
      (void (*)(void))ossl_cipher_generic_get_ctx_params },                    \
    { OSSL_FUNC_CIPHER_SET_CTX_PARAMS,                                         \
      (void (*)(void))ossl_cipher_var_keylen_set_ctx_params },                 \
    { OSSL_FUNC_CIPHER_GETTABLE_PARAMS,                                        \
      (void (*)(void))ossl_cipher_generic_gettable_params },                   \
    { OSSL_FUNC_CIPHER_GETTABLE_CTX_PARAMS,                                    \
      (void (*)(void))ossl_cipher_generic_gettable_ctx_params },               \
    { OSSL_FUNC_CIPHER_SETTABLE_CTX_PARAMS,                                    \
     (void (*)(void))ossl_cipher_var_keylen_settable_ctx_params },             \
    OSSL_DISPATCH_END                                                          \
};
```

上のコードを読むと、どうやら `alg##_##kbits##_##lcmode##_newctx` が `ossl_cipher_generic_initkey` といういかにも汎用関数っぽい名前のやつに `ossl_prov_cipher_hw_blowfish_ecb` を渡していることが分かる。おそらく ``ossl_prov_cipher_hw_blowfish_ecb``の返り値が中でいい感じに使われているんだろう。

じゃあ `alg##_##kbits##_##lcmode##_newctx` はどうやって呼ばれるんだろうと思うと、これは `OSSL_FUNC_CIPHER_NEWCTX` というタグとペアにされている。おそらくEVPの最初の方でいい感じに初期化されるんでしょう。こいつを含んでいる `OSSL_DISPATCH` 型の構造体は `static` ではないので、これで参照のチェーンは繋げられる。

具体的なイメージを掴むため `OSSL_FUNC_CIPHER_UPDATE` とペアになっている `ossl_cipher_generic_##typ##_update` の実装を見てみる。今は `typ` に `block` が渡されているので、 `ossl_cipher_generic_block_update` で code searchしてみると実装が出てくる。
([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/providers/implementations/ciphers/ciphercommon.c#L243))

`ossl_cipher_generic_block_update` は `ctx->tlsversion` が0のときと非0のときで違うロジックが実行されるようになっている。EVP経由でcipherだけするときには `ctx->tlsversion` は0になっていそう？その場合はL328からが本編になる。
([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/providers/implementations/ciphers/ciphercommon.c#L328))

いろいろバリデーションしたり~~パディングを調整したり~~しているが、最終的には `ctx->hw->cipher` を呼び出していることが分かる。この文脈での `ctx` は `PROV_CIPHER_CTX` のことで、 `ctx->hw` は さっき見た `PROV_CIPHER_HW*` として宣言されているので、実際に `ossl_prov_cipher_hw_blowfish_ecb` 経由で返された `crypto/bf` へのバインディングが呼ばれていそうに見える。
([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/providers/implementations/include/prov/ciphercommon.h#L96))

### `ossl_cipher_generic_block_update` を更に読む

([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/providers/implementations/ciphers/ciphercommon.c#L328))

`ctx->tlsversion == 0` のときにこの関数の挙動に大きく影響するパラメータは2つある。

- `ctx->bufsz` が0以上かどうか
- `ctx->blocksize` が `ctx->bufsz` と一致しているかどうか

これらは実はどっちもバッファの処理に関連している。固定長のブロックを処理するというアルゴリズムであるということと、 `ossl_cipher_generic_block_update` は繰り返し呼んで逐次的に入力を与えるためのインターフェースであるということの関係上、ブロック長に満たなかったぶんのデータはバッファに貯めておいて次回にまとめて処理する必要があるのだと思われる。

実際にコードを読んでみる。

```c
    if (ctx->bufsz != 0)
        nextblocks = ossl_cipher_fillblock(ctx->buf, &ctx->bufsz, blksz,
                                           &in, &inl);
    else
        nextblocks = inl & ~(blksz-1);
```

`nextblocks` は今回 `in` から直接読んで処理するバイト数。 `blksz` は `ctx->blocksize` のエイリアス。既に前回からの持ち越し分があれば `in` を使ってバッファを埋めその分は `nextblocks` から抜いておき、そうでない場合は `blksz` が2の累乗であることを仮定して、入力の長さを `blksz` の倍数に切り捨てている。

```c
    if (ctx->bufsz == blksz && (ctx->enc || inl > 0 || !ctx->pad)) {
        if (outsize < blksz) {
            ERR_raise(ERR_LIB_PROV, PROV_R_OUTPUT_BUFFER_TOO_SMALL);
            return 0;
        }
        if (!ctx->hw->cipher(ctx, out, ctx->buf, blksz)) {
            ERR_raise(ERR_LIB_PROV, PROV_R_CIPHER_OPERATION_FAILED);
            return 0;
        }
        ctx->bufsz = 0;
        outlint = blksz;
        out += blksz;
    }
```

これは前回持ち越し分からのバッファがある場合の処理。mikutterの使い方では関係ないが一応読んでおくと、バッファがブロックサイズぶんだけ溜まっていたら先に `ctx->hw->cipher` に渡して放出しておく。 `outlint` はおそらく `outl_intermediate` の意味。 `outl` は出力の長さを返すためのポインタ引数になっているので、関数の最後で1回代入する以外で逐次的にいじりたくないという気持ちだと思われる。

```c
    if (nextblocks > 0) {
        if (!ctx->enc && ctx->pad && nextblocks == inl) {
            if (!ossl_assert(inl >= blksz)) {
                ERR_raise(ERR_LIB_PROV, PROV_R_OUTPUT_BUFFER_TOO_SMALL);
                return 0;
            }
            nextblocks -= blksz;
        }
        outlint += nextblocks;
        if (outsize < outlint) {
            ERR_raise(ERR_LIB_PROV, PROV_R_OUTPUT_BUFFER_TOO_SMALL);
            return 0;
        }
    }
```

処理すべきブロックがあるときにバリデーションを走らせて、投機的に `outlint` を増やしている。出力がバッファにちゃんと収まるかのチェックも兼ねている。 `if (!ctx->enc && ...` は復号時の処理なのでここでは関係ないが、パディングされている暗号文のときはパディングの扱いが特殊なので、末尾の処理を `ossl_cipher_generic_block_final` に押し付けるため処理するデータ長を調整している。assertのエラーコードはおかしい気がする。

```c
    if (nextblocks > 0) {
        if (!ctx->hw->cipher(ctx, out, in, nextblocks)) {
            ERR_raise(ERR_LIB_PROV, PROV_R_CIPHER_OPERATION_FAILED);
            return 0;
        }
        in += nextblocks;
        inl -= nextblocks;
    }
```

本編の処理。さっき見たように、 `ctx->hw->cipher` を使って入力を暗号化して `out` に書き出している。

```c
    if (inl != 0
        && !ossl_cipher_trailingdata(ctx->buf, &ctx->bufsz, blksz, &in, &inl)) {
        /* ERR_raise already called */
        return 0;
    }
```

余った入力をバッファに貯めておく処理。

### `ossl_cipher_generic_block_final` を読む

([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/providers/implementations/ciphers/ciphercommon.c#L384))

先述のように、ブロック暗号は一定のブロック長（Blowfish ECBの場合は8バイト）の単位で暗号化を行うため、データ長がブロック長の倍数でないときはあまりが発生する。`ossl_cipher_generic_block_final` は余ったデータの処理を行う。Rubyコードでは `cipher.final` がこれに相当している。

パディングは `ossl_cipher_padblock` という小さい関数がやっていて、 `ctx->buf` にパディングを詰めてあまりの部分の長さを調整するという単純な方法になっている。
([link](https://github.com/openssl/openssl/blob/11f69aa50771d50151fa24c55fd0858db30517df/providers/implementations/ciphers/ciphercommon_block.c#L82))

**パディングの処理には注意すべき点が2点ある。**

- パディングの値は0ではなく、**パディングの長さが使われる。**
    - 例：5バイト埋める場合、`out = {…, 5, 5, 5, 5, 5}`
- パディングは**必ず1バイト以上存在する。**
    - 例：入力が10バイトの場合、出力は16バイト（パディング6バイト）
    - 例：入力が16バイトの場合、出力は24バイト（パディング8バイト）

## まとめ

厳密に確かめるにはもっと深掘りする必要があるが、読んでいない部分が非常識な壊れ方をしていない限り、mikutterの使い方で文字列を暗号化すると、入力を64ビットごとのブロックに分割しつつ `BF_ecb_encrypt` が逐次呼び出されるであろうことが分かる。

つまり復号部は `BF_ecb_encrypt` ([link](https://github.com/openssl/openssl/blob/456e6ca5d73972cdb4228e6c5ec9acdf19237308/crypto/bf/bf_ecb.c#L31)) と `BF_decrypt` をRubyで再実装すればよい。

- 復号は`encrypt == 0` での `BF_ecb_encrypt` の呼び出しとして表現されていることに注意。
- `BF_ROUNDS` は `bf_local.h` の中でdefineされているが、16以外にはならないっぽい。歴史的経緯？
- 復号された平文はパディングを含んでいるので、適切にドロップする必要がある。

[実装してパッチにした](https://dev.mikutter.hachune.net/issues/1585#note-10)。

### 未確認の実装

さすがに常識的な実装になっているだろうと予想して確認をスキップしたものたち

- OpenSSLが実際に “bf-ecb” という文字列からproviderを探し当ててくるロジック
- `EVP_CIPHER` の初期化フロー
- `PROV_CIPHER_CTX` の初期化フロー
    - `cipher_hw_blowfish_ecb_cipher` はこの `ctx->blocksize` が8であることを前提に書いてある。
        - `IMPLEMENT_var_keylen_cipher` の `blkbits` に64が渡されているのでそれっぽさはある。
    - `ctx->tlsversion` は本当に0になっているのか？
    - `ctx->pad` は本当に `true` になっているのか？