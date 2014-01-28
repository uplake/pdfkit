# This regular expression is used for splitting a string into wrappable words
WORD_RE = /([^ ,\/!.?:;\-\n"]*[ ,\/!.?:;\-"]*)|\n/g
{EventEmitter} = require 'events'
LineWrapper = require './line_wrapper'


class StyledLineWrapper extends LineWrapper
        
    wrap: (paragraphs, options) ->
        indent = options.indent or 0
        charSpacing = options.characterSpacing or 0
        wordSpacing = options.wordSpacing is 0
        @columns = options.columns or 1
        @columnGap = options.columnGap ? 18 # 1/4 inch
        @lineWidth =  (options.width - (@columnGap * (@columns - 1))) / @columns
        @startY = @document.y
        @column = 1
        
        # calculate the maximum Y position the text can appear at
        @maxY = @startY + options.height
        
        # make sure we're actually on the page 
        # and that the first line of is never by 
        # itself at the bottom of a page (orphans)
        nextY = @document.y + @document.currentLineHeight(true)
        if @document.y > @maxY or nextY > @maxY
            @nextSection()
        
        # word width cache
        wordWidths = {}
        
        @emit 'sectionStart', options, this

        {getStyle, setStyle} = options
        style = null

        doc_width = @document.widthOfString.bind(@document)
        width = (string) ->
            setStyle style
            doc_width string, options

        lineFragments = []
        buffer = ''
        wc = 0
        
        doLine = =>
            pushBuf()
            options.textWidth = (@lineWidth - spaceLeft) + wordSpacing * (wc - 1)
            {x, y} = @document
            for {buffer, style, w}, ii in lineFragments
                setStyle style
                # options.wordCount = wc # trying to make justification work, doesn't
                @emit 'fragment', buffer, x, y, options, this
                x += w

            @emit 'line', '', options, this
            lineFragments = []

        pushBuf = =>
            #don't push buffer if it's the first word we've seen
            if style?
                lineFragments.push {buffer, style, w: width(buffer), wc}

            # start new buffer
            buffer = ''


        for text, i in paragraphs
            @emit 'firstLine', options, this
            
            # split the line into words
            words = text.match(WORD_RE) or [text]
            console.log {words} if @document._fontSize is 9
                          
            # space left on the line to fill with words
            spaceLeft = @lineWidth - indent
            options.lineWidth = spaceLeft
            
            len = words.length
            buffer = ''
            lineFragments = []
            wc = 0

            for word, wi in words

                newstyle = getStyle i, wi, word
                if newstyle?
                    pushBuf()
                    style = newstyle

                wordWidthsForStyle = wordWidths[style] ?= {}

                unless (w = wordWidthsForStyle[word])?
                    w = wordWidthsForStyle[word] = width(word, options) + charSpacing + wordSpacing

                if w > spaceLeft or word is '\n'
                    doLine()
                                        
                    # if we've reached the edge of the page, 
                    # continue on a new page or column
                    if @document.y > @maxY
                        @nextSection()
                            
                    # reset the space left and buffer
                    spaceLeft = @lineWidth - w
                    buffer = if word is '\n' then '' else word
                    wc = 1
                            
                else
                    # add the word to the buffer
                    spaceLeft -= w
                    buffer += word
                    wc++
                    # if @document._fontSize is 24
                    #     console.log "adding word:", {word, buffer}
                        
            # add the last line
            @lastLine = true
            @emit 'lastLine', options, this
            doLine()
            
            # make sure that the first line of a paragraph is never by 
            # itself at the bottom of a page (orphans)
            nextY = @document.y + @document.currentLineHeight(true)
            if i < paragraphs.length - 1 and nextY > @maxY
                @nextSection()
                
        @emit 'sectionEnd', options, this
                    
            
module.exports = StyledLineWrapper