LineWrapper = require '../lib/line_wrapper'
PDFDoc = require('../lib/document')
doc = new PDFDoc
# doc.scale 1.5 # annotations don't honor transformations
_w = 1
until doc.pages.length > 1 
    doc.fontSize 8 + 2*_w
    wid = Math.min _w*100, doc.page.width - doc.page.margins.left - doc.page.margins.right
    y = if _w is 6
        doc.page.height - doc.page.margins.bottom - 2*doc.currentLineHeight() 
    else
        doc.y
    doc.text """
    #{_w}. This is some text that will occupy more than one line with a width of #{wid}. I will underline each group of two or more consonants and strike each group of two or more vowels.
    """, 72, y,
        width: wid
        textMap: yes
    doc.moveDown()

    {textMap} = doc

    # annotate based on regexps
    textMap.highlight(/this .+ line/i)
        .underline(if _w is 6 then /roup of tw/g else /[^aeiou\d\W]{2,}/g)
        .strike(/[aeiou]{2,}/g)

    # textMap has a lines property with an array of broken lines
    # each element of the lines array is an array of words
    # each line and word element has {x, y, w, h} properties
    word = textMap.lines[2].words[3] # get dims of a word of a line of text
    if word?
        {x, y, w, h} = word
        doc.rectAnnotation x-1, y-3, 3+doc.widthOfString("#{word}".replace /\s+/, ''), h+6

    for rect in textMap.rects # the textMap itself also has array of {x, y, w, h} properties
        {x, y, w, h, pageIndex} = rect
        doc.page = doc.pages[pageIndex]
        doc.rect x-2, y-2, w+4, h+4 # draw a rect around the block of text
        doc.moveTo( x + wid, y).lineTo(x + wid, y+h) # the textMap probably isn't exactly as wide as wid
        doc.stroke()
    _w++

doc.addPage()
_style = {
    PLAIN: 0
    BOLD: 1
    ITAL: 2
}
sp = ' ' # need for leading space
textChunks = []
WORD_RE = /([^ ,\/!.?:;\-\n]*[ ,\/!.?:;\-]*)|\n/g
styles = 
    '*': _style.BOLD
    '_': _style.ITAL
    '': _style.PLAIN
processStr = (str, style = _style.PLAIN) ->
    pat = /([\w\W]+?)([\*_]|$)/g
    styleMap = []
    words = []
    while (res = pat.exec str)
        [match, text, nextMarkUp] = res
        # console.log text, text.match WORD_RE
        # console.log {match, text, nextMarkUp, style}
        styleMap[words.length] = style
        words.push (text.match(WORD_RE) or [text])...
        textChunks.push 
            text: text
            style: style
        style ^= styles[nextMarkUp]
    {text: words, styleMap}

makeStyleMap = (text, style = _style.PLAIN) ->
    map = []
    paragraphs = for paragraph in text.split '\n'
        styleMap = []
        words = for word, word_i in (paragraph.match(WORD_RE) or [paragraph])
            word.replace /^([\*_])|([\*_])(?=\W*$)/g, (match, leadingMarkup, trailingMarkup) ->
                # console.log {word, match, leadingMarkup, trailingMarkup}
                style ^= styles[match]
                if leadingMarkup?
                    styleMap[word_i] = style
                else
                    styleMap[word_i+1] = style

                ''
        map.push styleMap
        words.join ''
    {
        text: paragraphs.join '\n'
        styleMap: map
    }

{text, styleMap}  = makeStyleMap """
*It is a truth universally acknowledged, that a single _man _in possession of a good fortune, must be in want of a wife*.
However little known _the *feelings* or *views* _of such a man may be on his first entering a neighbourhood, this *truth* is so well fixed in the minds of the surrounding families, that he is considered the _rightful property of some one or other of their daughters_.
"My dear *Mr. Bennet*," said his lady to him one day, "have you heard that _Netherfield Park_ is let at last?"
*Mr. Bennet* replied that he had not.
"But it *is*," returned she; "for *Mrs. Long* has _just *been* here_, and she *told me _all about_ it*."
*Mr. Bennet* made no answer.
"""
console.log {text, styleMap}

baseFont = 'Times'
left = 72

setStyle = (style) ->
    suffix =  switch style
        when _style.PLAIN then 'Roman'
        when _style.BOLD then 'Bold'
        when _style.ITAL then 'Italic'
        when _style.ITAL | _style.BOLD then 'BoldItalic'
        else null
    return unless suffix?
    doc.font "#{baseFont}-#{suffix}"

for size in [9..24]
    doc.fontSize size
    defaultIndent = size*2.5
    textMap = null

    doc.text size

    doc.styledText text, 
        getStyle: (pi, wi, word) ->  styleMap[pi][wi]
        setStyle: (style) -> setStyle style
        indent: size*2
        paragraphGap: 6
        lineGap: size/4
        characterSpacing: size/50
        # align: 'justify' # FAIL!

    doc.moveDown()


    # trailingSpace = ''
    # for chunk, chunki in textChunks
    #     setStyle chunk.style

    #     {text} = chunk

    #     if textMap?
    #         {lines} = textMap
    #         # console.log {lines}, ''+lines[0], {trailingSpace}
    #         if lines.length > 0
    #             words = lines[lines.length-1].words
    #             lastWord = words[words.length-1]
    #             {y, w, h} = lastWord
    #             [leadingSpace] = text.match /^\s*/
    #             indent = (lastWord.x + w) - x + doc.widthOfString(trailingSpace+leadingSpace)
    #     else
    #         indent = defaultIndent
    #         x = left
    #         y = doc.y

    #     for line, ii in text.split('\n')
    #         if ii > 0
    #             y += doc.currentLineHeight(true) 
    #             indent = defaultIndent
    #         # console.log {chunki, line, x, y, indent, lastWord}, lines.length if size is 23
    #         doc.text line, x, y,
    #             textMap: yes
    #             indent: indent
    #             # width: no # don't use linewrapper... not good
    #             # height: doc.page.height - y # prevents orphan control
    #             columns: if size < 13 then 2 else 1
            

    #     [trailingSpace] = line.match /\s*$/
    #     {textMap} = doc

    # doc.moveDown()


doc.write './styled_text.pdf'

