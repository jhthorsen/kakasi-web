#!perl
use Mojolicious::Lite;

use IPC::Run 'run';
use Mojo::Util qw(decode trim xml_escape);

get '/' => sub {
  my $c = shift;
  $c->render('index');
};

post '/translate' => sub {
  my $c = shift->render_later;
  my $input = $c->req->json->{text} || [];
  my $mode = $c->req->json->{mode} || '';
  my @cmd = $mode eq 'h' ? qw(-JH -s) : $mode eq 'k' ? qw(-HK -JK -s) : $mode eq 'r' ? qw(-Ha -Ka -Ja -Ea -ka -s) : qw(-JH -f -w);

  Mojo::IOLoop->subprocess->run_p(sub {
    unshift @cmd, qw(kakasi -i utf8 -o utf8);
    my $stdin = join "\n", @$input;
    run \@cmd, \$stdin, \my $stdout, \my $err;
    die $err if $err;

    my @output;
    for my $line (split /\n/, $stdout) {
      my @words;
      for my $word (split /\s/, $line) {
        my $rt = $word =~ s!\[(.*)\]$!! ? xml_escape $1 : undef;
        $word = xml_escape $word;
        push @words, defined $rt ? qq(<ruby class="word"><rb>$word</rb><rp>(</rp><rt>$rt</rt><rp>)</rp></ruby>)
          : length $word ? qq(<span class="word">$word</span>) : qq(<span class="empty">&nbsp;</span>);
      }

      push @output, join '<span class="space">&nbsp;</span>', map { $_ } @words;
    }

    push @output, '' until @output == @$input;

    return \@output;
  })->then(sub {
    my $output = shift;
    $c->render(json => {text => [map { decode 'UTF-8', $_ } @$output]});
  })->catch(sub {
    $c->render(json => {error => shift});
  });
};

app->start;

__DATA__
@@ index.html.ep
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    @import "https://fonts.googleapis.com/css2?family=Open+Sans&family=Roboto&display=swap";
    %= include 'kakasi', format => 'css'
  </style>
</head>
<body>
  <form>
    <header class="header">
      <h1 class="py-4">Kakasi powered online furigana editor</h1>
    </header>
    <main class="io">
      <table class="io-table">
        <thead class="io-head">
          <tr>
            <th>Input</th>
            <th>
              Output
              <select name="mode" class="form-select form-select-sm" aria-label="Output">
                <option value="f">Furigana</option>
                <option value="h">Hiragana</option>
                <option value="k">Katekana</option>
                <option value="r">Romanji</option>
              </select>
            </th>
            <th>Notes</th>
            <th>
              <button type="button" class="close text-danger" aria-label="Delete">
                <span aria-hidden="true">&times;</span>
              </button>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="io__input"><div contenteditable="true"></div></td>
            <td class="io__output"></td>
            <td class="io__notes"><div contenteditable="true"></div></td>
            <td class="io__remove">
              <button type="button" class="close text-danger" aria-label="Delete">
                <span aria-hidden="true">&times;</span>
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </main>
  </form>
  <script>
    %= include 'kakasi', format => 'js'
    const translateUrl = '<%= url_for '/translate' %>';
    new Kakasi({translateUrl}).attach(document.querySelector('form'));
  </script>
</body>

@@ kakasi.css.ep
html,
body {
  font-family: Roboto, sans;
  font-size: 18px;
  margin: 0;
  padding: 0;
}

body {
  background: #f6f6f6;
}

button {
  background: #fff;
  font-size: 16px;
  border: 1px solid #939393;
  border-radius: 3px;
  padding: 0.1rem 0.2rem;
  cursor: pointer;
}

select {
  background: #fff;
  font-size: 16px;
  border: 1px solid #939393;
  border-radius: 3px;
  padding: 0.1rem 0.2rem;
}

ruby {
  display: inline-block;
  position: relative;
  border: 0 !important;
}

ruby rt {
  font-size: 0.6em;
  text-align: center;
  width: 100%;
  display: block;
  position: absolute;
  top: -0.2em;
  left: 0;
  transition: transform 0.2s;
  transform-origin: bottom;
}

ruby:hover rt {
  color: #4488aa;
  transform: scale(1.4);
}

.header {
  text-align: center;
}

.header h1 {
  font-size: 2rem;
  margin: 2rem;
  position: relative;
}

.io {
  padding: 2rem;
}

.io-table {
  width: 100%;
  border-spacing: 0;
}

.io-table td,
.io-table th {
  padding: 0.5rem 0.3rem;
}

.io-head th {
  vertical-align: middle;
  text-align: left;
  border-bottom: 1px solid #4488aa;
}

.io-head .col {
  align-self: center;
}

.io-table tbody tr td {
  vertical-align: top;
  border-bottom: 1px dotted #7b9fb0;
}

.io__input,
.io__notes,
.io__output {
  line-height: 2rem;
}

.io__remove {
  width: 1%;
}

.io__input,
.io__output {
  width: 40%;
}

.word,
.word rb {
  border-bottom: 2px solid transparent;
}

.space {
  padding: 0 0.2rem;
}

.word:hover,
.word:hover rb {
  border-bottom-color: #4488aa;
}

[contenteditable]:focus,
[contenteditable]:hover {
  outline: 1px dotted #4488aa;
  outline-offset: 0.2rem;
}

@@ kakasi.js.ep
class Kakasi {
  constructor(params) {
    this.translateUrl = params.translateUrl;
  }

  addRow() {
    const trNext = this.firstRow.cloneNode(true);
    trNext.querySelector('.io__output').innerHTML = '';
    this.select('-input', trNext).innerHTML = '';
    this.firstRow.parentNode.insertBefore(trNext, null);
    this._addTrEventHandlers(trNext);
    return trNext;
  }

  attach(form) {
    this.form = form;
    this.firstRow = form.querySelector('.io tbody tr');
    this._addTrEventHandlers(this.firstRow);
    form.addEventListener('submit', this.onSubmit.bind(this));
    this.select('-mode').addEventListener('change', this.translate.bind(this));
    this.load();
    this.translate();
    this.select('-input', this.firstRow).focus();
  }

  ensureEmptyRow() {
    const lastInput = this.selectAll('-input').pop();
    if (!lastInput) return this.addRow();
    if (lastInput.textContent.match(/\S/)) return this.addRow();
  }

  load() {
    let data = localStorage.getItem('kakasi_body');
    if (!data) return;
    data = JSON.parse(data);
    this.select('-mode').value = data.mode;
    data.text.forEach((line, i) => {
      const tr = i ? this.addRow() : this.firstRow;
      this.select('-input', tr).textContent = line;
    });
  }

  mode(val) {
    if (!val) return this.select('-mode').value;
    this.select('-mode').value = val;
    return this;
  }

  onSubmit(e) {
    e.preventDefault();
    this.translate();
  }

  select(sel, parent = this.form, method = 'querySelector') {
    if (sel == '-input') return parent[method]('.io__input [contenteditable]');
    if (sel == '-mode') return parent[method]('[name=mode]');
    if (sel == '-output') return parent[method]('.io__output');
    return parent[method](sel);
  }

  selectAll(what, parent) {
    return [].slice.call(this.select(what, parent, 'querySelectorAll'), 0);
  }

  translate() {
    const text = this.selectAll('-input').map(el => el.textContent.trim());
    const body = JSON.stringify({mode: this.mode(), text});

    localStorage.setItem('kakasi_body', body);
    fetch(this.translateUrl, {method: 'POST', body}).then(res => {
      return res.json();
    }).then(json => {
      this.selectAll('-output').forEach(el => (el.innerHTML = json.text.shift()));
      this.ensureEmptyRow();
    }).catch(err => {
      alert(err);
    });
  }

  _addTrEventHandlers(tr) {
    let tid;
    this.select('-input', tr).addEventListener('keydown', e => {
      if (tid) clearTimeout(tid);
      tid = setTimeout(this.translate.bind(this), 350);

      if (e.key == 'Enter') {
        e.preventDefault();
      }
    });
  }
}
