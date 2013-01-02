// import macro.HTMLTemplate;

// git@github.com:sledorze/Parsex.git
import ArrayExtensions;
import com.mindrocks.text.Parser;
import ReflectionExtensions;
import ExprExtensions;
using com.mindrocks.text.Parser;
import com.mindrocks.functional.Functional;
using com.mindrocks.functional.Functional;
using com.mindrocks.macros.LazyMacro;

import haxe.macro.Expr;
import haxe.macro.Context;


// for debugging return string
typedef E = 
#if macro
  Expr
#else
  String
#end

// this get's parsed {{{
enum Attribute {
  attr_expr(e:E); // must recturn hash or {} object
  attr_name_value(name:String, value:String);
  attr_name_expr_as_value(name:String, expr:E);
}

enum ParsedTemplateItem {
  text(s:String); // html
  expr(e:E, quoted: Bool); // e should return a string

  tag(name:String, attributes:Array<Attribute>, contents:TemplateContent);

  control_if(cond:E, then_: TemplateContent, else_: TemplateContent /* can be empty list*/);

  // for (..) true; will be parsed true will then be substituted by the content
  control_for(for_:E, content: TemplateContent);
  
  // case ..
}
typedef TemplateContent = Array<ParsedTemplateItem>;
// }}}

typedef CurrIndent = {
  s:String,
  p:Parser<String, Void>
}

// parsing the template files is that simple, no backtracking required.
// we just throw an Exception on error
typedef ParserState = {
  s:String,
  i:Int
};

#if macro
class ExprBuilder {
  public var items:Array<Expr>;
  public function new() {
    items = [];
  }

  public function s(s:String) {
    var e:Expr;
    if (items.length > 0){
      var last_s = ReflectionExtensions.value_at_path(ArrayExtensions.last(items).expr, ["EConst",0,"CString",0]);
      if (last_s != null){
        items[items.length-1] = macro $(last_s + s);
        return;
      }
    }
    items.push(macro $(s));
  }

  public function expr(e:Expr) {
    items.push(e);
  }
}
#end

// TODO: think about where to use return LazyMacro.lazy({
class TemplateParser {

  static public var autoclose = ["meta","img","link","br","hr","input","area","param","col","base"];

  static inline function code(ps: ParserState) {
    return StringTools.fastCodeAt(ps.s, ps.i);
  }

  @:macro static function c(char_str: ExprOf<String>):ExprOf<Int> {
    var i:Int = StringTools.fastCodeAt(ReflectionExtensions.value_at_path(char_str.expr, ["EConst",0,"CString",0]), 0);
    return macro $(i);
  }

  static function exprToCode(char_str:Expr):Int{
    return StringTools.fastCodeAt(ReflectionExtensions.value_at_path(char_str.expr, ["EConst",0,"CString",0]), 0);
  }

  @:macro static function is_string(ps: ExprOf<ParserState>, string:ExprOf<String>):ExprOf<Bool> {
    var s = ReflectionExtensions.value_at_path(string.expr, ["EConst",0,"CString",0]);
    return macro {
      if ($ps.s.substr($ps.i, $ps.s.length) == $string){
        $ps.i += $string.length;
        true;
      } else {
        false;
      }
    };
  }

  @:macro static function is_char(ps: ExprOf<ParserState>, char:ExprOf<String>):ExprOf<Bool> {
    return macro (!eof($ps) && StringTools.fastCodeAt($ps.s, $ps.i) == $(exprToCode(char)));
  }

  @:macro static function expect_char(ps: ExprOf<ParserState>, char:ExprOf<String>):ExprOf<Bool> {
    return macro if (StringTools.fastCodeAt($ps.s, $ps.i) != $(exprToCode(char))) parse_failure($ps,  "expected :`"+$char+"`");
  }

  static public function spaces(count:Int, p:ParserState) {
    var i_ = p.i;
    try{
      while (count > 0 && is_char(p, " ")) count --;
      return true;
    }catch(e:Dynamic){
      p.i = i_;
      return false;
    }
  }

  static inline public function eof(ps:ParserState) {
    return ps.i >= ps.s.length;
  }

  static inline public function ignore_spaces(ps:ParserState) {
    while (is_char(ps, " ")) ps.i++;
  }

  static public function parse_name_like(ps:ParserState) {
    var name = "";
    while (!eof(ps)) {
      var c = code(ps);
      if ((c >= 97 && c <= 122) || c == 95){
        // a-z                     _
        name += ps.s.charAt(ps.i);
        ps.i++;
      } else break;
    }
    return name;
  }

  static public function parse_attr_value(ps) {
    var c = code(ps);
    if (c == 34 /*"*/ || c == 39 /* ' */)
      ps.i++;
    else
      parse_failure(ps, "attr value expected quoted by ' or \"");
    var start = ps.i;
    while (!eof(ps) && !is_char(ps, "\"") && !is_char(ps, "'")) ps.i++;
    ps.i++;
    return ps.s.substr(start, ps.i - start -1);
  }

  static public function parse_tag(ii:Int, ps:ParserState):ParsedTemplateItem {
    var name = 'div';
    var attributes = [];

    var add_attr = function(name, value){
      // add to existing class entry:
      var attr_added = false;
      for(i in 0...attributes.length){
        switch(attributes[i]) {
          case attr_name_value(n_, c_):
             if (n_ == name){
               if (name == "class"){
                 attributes[i] = attr_name_value(name, c_+" "+value);
                 attr_added = true;
               } else {
                  parse_failure(ps, "duplicate attr definition "+name);
               }
             }
             break;
          case _:
        }
      }
      if (!attr_added) attributes.push(attr_name_value(name, value));
    };

    var add_id = function(name){
      // add to existing class entry:
      var attr_added = false;
      for(i in 0...attributes.length){
        switch(attributes[i]) {
          case attr_name_value("class", c_):
             attributes[i] = attr_name_value("class", c_+" "+name);
             attr_added = true;
             break;
          case _:
        }
      }
    };

    // name:String, attributes:Array<Attribute>, contents:TemplateContent
    switch (code(ps)) {
      // tag name after %
      case 37 /*%*/: 
        // parse tag name
        ps.i++; name = parse_name_like(ps);
      case _:
    }

    while (!eof(ps)){
      switch (code(ps)) {
        case 46 /*.*/:
          ps.i++;
          var name = parse_name_like(ps);
          add_attr("class", name);
        case 35 /*#*/:
          ps.i++;
          var name = parse_name_like(ps);
          add_attr("id", name);
        case _:
          break;
      }
    }
    // parse attributes
    if (is_char(ps, "(")){
        ps.i++;
        ignore_spaces(ps);
        while (!eof(ps) && !is_char(ps, ")")){
          // parse attributes
          ignore_spaces(ps);
          if (is_char(ps, "$")){
            // injections
            ps.i++;
            attributes.push(attr_expr(parse_haxe_expr(ps)));
          } else {
            // hard coded name value pair
            var name = parse_name_like(ps);
            expect_char(ps, "="); ps.i++;
            if (is_char(ps, "$")){
              ps.i++;
              attributes.push(attr_name_expr_as_value(name, parse_haxe_expr(ps)));
            } else {
              add_attr(name, parse_attr_value(ps));
            }
          }

          ignore_spaces(ps);
        }
        expect_char(ps, ")"); ps.i++;
    }
    // parse content if any
    var contents = [];
    if (is_char(ps, "=")){
      // one line
      parse_text(null, ps, contents);
      if (!eof(ps)){  expect_char(ps, "\n"); ps.i++; }
    } else if (is_char(ps, "!")){
      // one line
      ps.i++;
      expect_char(ps, "=");
      ps.i--;
      contents = [];
      parse_text(null, ps, contents);
      if (!eof(ps)){ expect_char(ps, "\n"); ps.i++; }
    } else {
      if (!eof(ps)){
        expect_char(ps, "\n"); ps.i++;
        // now test for items having one additional indentation level ..
        contents = [];
        parse_template_items(ii + 2, ps, contents);
      }
    }
    if (ArrayExtensions.contains(autoclose,name) && contents != [])
      parse_failure(ps, "tag with children found which is not expected to have childs");
    return tag(name, attributes, contents);
  }

  static public function parse_failure(ps:ParserState, msg:String) {
    throw msg+" at bytepos "+ ps.i +": "+ps.s.substr(ps.i);
  }

  static public function walk_haxe_expr(ps:ParserState, repeat:Bool = false) {

    ignore_spaces(ps);
    while (true){
      var start = ps.i;
      var co = code(ps);
      switch (co){
        case 34 /* " */:
          // parse string
          ps.i++;
          while (true){
            var c = code(ps);
            if (c == 34){ ps.i++; break; }
            if (c == 92 /* \ */) ps.i += 2;
            else ps.i++;
          }
        case 40 /* ( */:
          ps.i++; walk_haxe_expr(ps, true);
          ignore_spaces(ps);
          expect_char(ps, ")"); ps.i++;
        case 123 /* { */:
          ps.i++; walk_haxe_expr(ps, true);
          ignore_spaces(ps);
          expect_char(ps, "}"); ps.i++;
        case _:
          if (co == 125 /* } */ || co == 41 /* ) */) break;
          // anything else such as foo.bar
          while (!eof(ps)){
            var c = code(ps);
            if ((c >= 97 && c <= 122) /* a-z */ || (c >= 65 && c <= 90) /* A-Z */ 
                || c == 95 /*_*/ || c == 46 /*.*/|| c == 63 /*?*/ || c == 58 /*:*/ || (c == 32 && repeat))
              ps.i++;
            else break;
          }
      }
      if (!repeat || start == ps.i) break;
    }
  }
  static public function parse_haxe_expr(ps:ParserState):E {
    var i = ps.i;
    walk_haxe_expr(ps);
    var s = ps.s.substr(i, ps.i - i);
#if macro
    return Context.parse(s, Context.currentPos());
#else
    return s;
#end
  }

  // for, while etc
  static public function parse_code(ii:Int, ps:ParserState):ParsedTemplateItem {
    expect_char(ps, ":"); ps.i++;
    if (ps.s.substr(ps.i, 2) == 'if'){
      // if
      ps.i += 2;
      ignore_spaces(ps);
      // todo , pass location of template string
      var cond_expr = parse_haxe_expr(ps);
      expect_char(ps, "\n"); ps.i++;
      var then_content = [];
      parse_template_items(ii+2, ps, then_content);
      var else_content = [];
      // else branch?
      var i = ps.i;
      if (spaces(ii, ps)){
        if (is_string(ps, ":else")){
          expect_char(ps, "\n"); ps.i++;
          parse_template_items(ii+2, ps, else_content); 
        } else {
          // we're done, no else branch
          ps.i = i;
        }
      }
      return control_if(cond_expr, then_content, else_content);

    } else if (ps.s.substr(ps.i, 2) == 'for') {
      // for
      throw "TODO: implement for";
    } else {
      parse_failure(ps, ":for or :if expected");
      return null; // dummy, parse_failure throwsn exception
    }
  }

  static public function parse_text_line(ps, r:Array<ParsedTemplateItem>) {
    // do not eat \n
    while (!eof(ps)){
      var c = code(ps);
      if (c == 33 /*!*/ || c == 61 /*=*/){
        // interpolation
        expect_char(ps, "{"); ps.i++;
        r.push(expr(parse_haxe_expr(ps), c == 61));
        expect_char(ps, "}"); ps.i++;
      } else {
        // text
        var s = "";
        var next = code(ps);
        while (next != null && next != 92 /* \n */){
          if (next == 92 /* \n */)
            break;
          else if (next == 36 /*$*/ || next == 33)
            // interpolation starts, so end
            break;
          else if (next == 92 /* \ */){
            // quote next char, ignore
            ps.i++;
          } else {
            // this can be optimized by using substring
            s += ps.s.charAt(ps.i);
          }
        }
        if (s != "")
          r.push(text(s));
      }
    }
  }

  // text is either:
  // = expr
  // != expr
  // text ${expr} !{expr} or such
  static public function parse_text(ii:Null<Int>, ps:ParserState, r:Array<ParsedTemplateItem> ) {
   // if initial indent is null don't eat trailing whitespace, this happens in parse_tag

    while (!eof(ps)){
      var i = ps.i;
      // optionally parse indent
      if (ii != null && !spaces(ii, ps))
        return;

      var code = code(ps);
      // stop if line is not a text line
      if (code == 37 /*%*/ || code == 46 /*.*/ || code == 35 /*#*/){
        if (ii == null) throw "unexpected";
        else {
          // no longer a text line, return
          ps.i = i;
          return;
        }
      }
      // expr lines:
      if (code == 61 /*=*/ || code == 33 /*!*/){
        var quoted = true;
        if (code == 33){ expect_char(ps, "="); ps.i++; quoted = false; }
        r.push(expr(parse_haxe_expr(ps), quoted));
        if (ii==null) return;
        expect_char(ps, "\n"); ps.i++;
      } else {
      // must be a text line ..
        parse_text_line(ps, r);
        if (ii==null) return;
        expect_char(ps, "\n"); ps.i++;
      }
    }
  }

  static function parse_template_items(ii:Int, ps: ParserState, r:TemplateContent){
    while (!eof(ps)){
      // drop spaces:
      var i = ps.i;
      if (!spaces(ii, ps)){ ps.i = i; break; }
      switch (code(ps)) {
        // tags
        case 37 /*%*/: r.push(parse_tag(ii, ps));
        case 46 /*.*/: r.push(parse_tag(ii, ps));
        case 35 /*#*/: r.push(parse_tag(ii, ps));

        // code
        case 58 /*:*/: r.push(parse_code(ii, ps));
        case _: parse_text(ii, ps, r);
      }
    }
  }

#if macro
  // the Expr evaluate to a String
  // later more complicated types such as string builders could be supported,
  // too. In the past I did some benchmarks - concatenating strings is that
  // optimized that it may not pay off using builders
  static public function template_content_to_expr(ptis:Array<ParsedTemplateItem>, e:
      {
        // html: String -> Expr,
        joinItems: Array<Expr> -> Expr, // this may try to optimize adjecent CString exprs
        quoteS: String -> String, // quote string for HTML
        quote: Expr -> Expr, // Expr evaluates to str, should return something quoting it
        attrs: Expr -> Expr, // expr is {} or hash, should return expr evaluating to html
        if_: Expr -> Expr -> Expr -> Expr,
        for_: Expr -> Expr -> Expr
      }
  ):Expr {
    var r = new ExprBuilder();
    for(pti in ptis){
      switch(pti) {
        case text(s):
          r.s(s);
        case expr(expr, quoted): 
          var e_ = expr;
          if (quoted) e_ = e.quote(e_);
          r.expr(e_);
        case tag(name, attributes, contents):
          // tag open
          r.s("<"+name);

          for (a in attributes){
            switch(a) {
              case attr_expr(e_): r.expr(e.attrs(e_));
              case attr_name_value(name, value):
                r.s(" ");
                r.s(name+"=\""+e.quoteS(value)+"\"");
              case attr_name_expr_as_value(name, expr):
                r.s(" "+name+"=\"");
                r.expr(e.quote(expr));
                r.s("\"");
            }
          }

          if (ArrayExtensions.contains(autoclose, name)){
            if (contents.length > 0)
              // internal error, should have been caught in parse_tag
              throw "bad, autoclosing tag but contents found!";
            r.s("/>");
          } else {
            r.s(">");
            r.expr(template_content_to_expr(contents, e));
            r.s("</"+name+">");
          }
        case control_if(cond, then_, else_):
          r.expr(e.if_(cond, template_content_to_expr(then_, e), else_ == null ? null : template_content_to_expr(else_, e)));
        case control_for(for_, content ):
          r.expr(e.for_(for_, template_content_to_expr(content,e) ));
      }
    }
    return e.joinItems(r.items);
  }
#end

  public static function parse_template(s:String):TemplateContent {
    // TODO: introduce caching!
    var ps = { s: s, i:0}
    while (is_char(ps, " ")) ps.i++;
    var initial_indent = ps.i;
    ps.i = 0;
    var r = [];
    parse_template_items(initial_indent, ps, r);
    return r;
  }


#if macro
  public static function template_to_str_expr(s:String):Expr {
    return template_content_to_expr(parse_template(s), {
        joinItems: function(items){
                    return switch(items.length) {
                      case 0: macro $("");
                      case 1: items[0];
                      case _:
                        var c = items.shift();
                        while (items.length > 0){
                          var next = items.shift();
                          c = macro $c + $next;
                        }
                        c;
                    }
                  },
        quoteS: function(s){ return StringTools.htmlEscape(s); },
        quote: function(e){ return macro StringTools.htmlEscape($e); },
        attrs: function(e){ return macro HTMLTemplate.attrsToHtml($e); },
        if_: function(cond, if_, else_){
                  var el = else_ == null ? (macro "") : else_;
                  return macro ($cond ? $if_ : $el);
              },
        for_: null
	// EFor( it : Expr, expr : Expr );
    });
  }
#end

}

/*
  samples see sample at Test.hx
*/
class HTMLTemplate {

#if !macro
  static public function attrsToHtml(a:Dynamic) {
    var s = "";
    if (Std.is(a, Hash)){
      var h: Hash<String> = cast(a);
      for(k in h.keys())
        s+=" "+k+"=\""+ StringTools.htmlEscape(h.get(k))+"\"";
    } else {
      for (k in Reflect.fields(a))
        s+=" "+k+"=\""+ StringTools.htmlEscape(Reflect.field(a,k))+"\"";
    }
    return s;
  }
#end

  @:macro static public function haml_like_str(template:Expr): Expr {
    return TemplateParser.template_to_str_expr(ReflectionExtensions.value_at_path(template.expr, ["EConst",0,"CString",0])); 
  }

  // @:macro static public function test(template:Expr): Expr {
  //   var e = macro {
  //     var c = 7;
  //     var d = 8;
  //   };
  //   trace(e);
  //   return ReflectionExtensions.value_at_path(e.expr, ["EBlock",0]);
  // }

  // @:macro static public function test2(e:Expr): Expr {
  //   trace(Context.getLocalType());
  //   return ReflectionExtensions.value_at_path(e.expr, ["EBlock",0]);
  // }
}

class Test {

  static function assert_equal(a, b) {
    if (a != b){
      trace(a);
      trace("expected");
      trace(b);
    }
  }

  @:macro static function test(template:ExprOf<String>, expected:ExprOf<String>):Expr {
    return macro {
      var r = HTMLTemplate.haml_like_str($template);
      if (r == $expected){
        Sys.println("ok");
      } else {
        Sys.println("=== ERROR: ");
        Sys.println("expected: "+$expected);
        Sys.println("got: "+r);
      }
    }
  }

  static function main() {

      // ../haxe-mw-extensions/lib/ExprExtensions.hx:5: { expr => EBlock([{ expr => EFor({ expr => EIn({ expr => EConst(CIdent(x)), pos => #pos(Test.hx|544 col 12| },{ expr => EArrayDecl([]), pos => #pos(Test.hx:544: characters 17-19) }), pos => #pos(Test.hx:544: characters 12-19) },{ expr => EConst(CIdent(true)), pos => #pos(Test.hx:544: characters 21-25) }), pos => #pos(Test.hx:544: characters 8-25) }]), pos => #pos(Test.hx:543: lines 543-545) }

    // ExprExtensions.trace({ for(x in []) true; });

    // test("%div.abc", "<div class=\"abc\"></div>");
    // test(".abc", "<div class=\"abc\"></div>");
    // test("%div.a.b", "<div class=\"a b\"></div>");
    // test("%div#abc", "<div id=\"abc\"></div>");
    // test("#abc", "<div id=\"abc\"></div>");

    // test("#abc(attr='xyz')", "<div id=\"abc\" attr=\"xyz\"></div>");
    // test("#abc(attr='xyz')", "<div id=\"abc\" attr=\"xyz\"></div>");
    // test("#abc(attr=$value )", "<div id=\"abc\" attr=\"X\"></div>");
    test("#abc(${attr: \"X\"})", "<div id=\"abc\" attr=\"X\"></div>");
    // trace(TemplateParser.parse_template("#abc(${attr: \"X\"})"));

    // test("#abc(attr=$value)zdf", "<div id=\"abc\" attr=\"X\">zdf</div>");

    // trace(TemplateParser.parse_template("#abc(attr=$value)"));

    // assert_equal(HTMLTemplate.haml_like_str(
    // '%div'),
    // '<div></div>'
    // );
    
  }

  static public function sample() {
    // Example illustrating all features.
    // If you don't know this style have a look at haml-lang.org to get an idea.

//     var html = HTMLTemplate.haml_like_str('
//     %div(class="first_level")%div.second_level foo
//     %p
//       some multiline text
//       with quoted expression ${"haxe expression"} and
//       an unquoted expression !{"<b>bold</b>"}

//       Thus a table can be written pretty easily:

//     %table%tr
//       %td foo
//       %td bar

//     #id_shorcut
//       This will expand to <div id="id_shorcut"></div>

//     :if (True)
//       .fine everything is fine
//     :else
//       .bad something went wrong

//     -# of course comments are supported
//     -#
//       and more haxe expressions
//       like a for loop - and dynamic tags are supported:
//     :for (i in [1,2,3])
//       %div(${class: "i_is_"+i} color=${i})=i
//     ')();

//     trace(html);
  }
  
}