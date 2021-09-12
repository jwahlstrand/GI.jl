function write_to_file(filename,toplevel)
    open(filename,"w") do f
        Base.println(f,"quote")
        Base.show_unquoted(f, toplevel)
        println(f)
        Base.println(f,"end")
    end
end

function output_exprs()
    body = Expr(:block)
    toplevel = Expr(:toplevel, body)
    exprs = body.args
    exports = Expr(:export)
    toplevel, exprs, exports
end
