/**
 * Implementation of support routines for synchronized blocks.
 *
 * Copyright: Copyright Digital Mars 2000 - 2011.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   Walter Bright, Sean Kelly
 */

/**
 * D implementation written and ported to tango by Iain Buclaw.
 */

module rt.compiler.gdc.critical_;

private
{
    debug(PRINTF) import tango.stdc.stdio;
    import tango.stdc.stdlib;

    version( linux )
    {
        version = USE_PTHREADS;
    }
    else version( FreeBSD )
    {
        version = USE_PTHREADS;
    }
    else version( OSX )
    {
        version = USE_PTHREADS;
    }
    else version( Solaris )
    {
        version = USE_PTHREADS;
    }

    version( Windows )
    {
        import tango.sys.win32.UserGdi;

        /* We don't initialize critical sections unless we actually need them.
         * So keep a linked list of the ones we do use, and in the static destructor
         * code, walk the list and release them.
         */
        struct D_CRITICAL_SECTION
        {
            D_CRITICAL_SECTION *next;
            CRITICAL_SECTION cs;
        }
    }
    else version( USE_PTHREADS )
    {
        import tango.stdc.posix.pthread;

        /* We don't initialize critical sections unless we actually need them.
         * So keep a linked list of the ones we do use, and in the static destructor
         * code, walk the list and release them.
         */
        struct D_CRITICAL_SECTION
        {
            D_CRITICAL_SECTION *next;
            pthread_mutex_t cs;
        }
    }
    else
    {
        /* Define a stub type for systems that don't support.  */
        version = NoSystem;

        struct D_CRITICAL_SECTION
        {
        }
    }
}


/* ================================= Win32 ============================ */

version( Windows )
{
    /******************************************
     * Enter/exit critical section.
     */

    static D_CRITICAL_SECTION *dcs_list;
    static D_CRITICAL_SECTION critical_section;
    static int inited;

    extern (C) void _d_criticalenter(D_CRITICAL_SECTION *dcs)
    {
        debug(PRINTF) printf("_d_criticalenter(dcs = x%x)\n", dcs);
        if (!dcs.next)
        {
            EnterCriticalSection(&critical_section.cs);
            if (!dcs.next) // if, in the meantime, another thread didn't set it
            {
                dcs.next = dcs_list;
                dcs_list = dcs;
                InitializeCriticalSection(&dcs.cs);
            }
            LeaveCriticalSection(&critical_section.cs);
        }
        EnterCriticalSection(&dcs.cs);
    }

    extern (C) void _d_criticalexit(D_CRITICAL_SECTION *dcs)
    {
        debug(PRINTF) printf("_d_criticalexit(dcs = x%x)\n", dcs);
        LeaveCriticalSection(&dcs.cs);
    }

    extern (C) void _STI_critical_init()
    {
        if (!inited)
        {
            debug(PRINTF) printf("_STI_critical_init()\n");
            InitializeCriticalSection(&critical_section.cs);
            dcs_list = &critical_section;
            inited = 1;
        }
    }

    extern (C) void _STD_critical_term()
    {
        if (inited)
        {
            debug(PRINTF) printf("_STI_critical_term()\n");
            while (dcs_list)
            {
                debug(PRINTF) printf("\tlooping... %x\n", dcs_list);
                DeleteCriticalSection(&dcs_list.cs);
                dcs_list = dcs_list.next;
            }
            inited = 0;
        }
    }
}

/* ================================= linux ============================ */

version( USE_PTHREADS )
{
    /******************************************
     * Enter/exit critical section.
     */

    static D_CRITICAL_SECTION *dcs_list;
    static D_CRITICAL_SECTION critical_section;
    static pthread_mutexattr_t _criticals_attr;

    extern (C) void _d_criticalenter(D_CRITICAL_SECTION *dcs)
    {
        if (!dcs_list)
        {
            _STI_critical_init();
            atexit(&_STD_critical_term);
        }
        debug(PRINTF) printf("_d_criticalenter(dcs = x%x)\n", dcs);
        if (!dcs.next)
        {
            pthread_mutex_lock(&critical_section.cs);
            if (!dcs.next) // if, in the meantime, another thread didn't set it
            {
                dcs.next = dcs_list;
                dcs_list = dcs;
                pthread_mutex_init(&dcs.cs, &_criticals_attr);
            }
            pthread_mutex_unlock(&critical_section.cs);
        }
        pthread_mutex_lock(&dcs.cs);
    }

    extern (C) void _d_criticalexit(D_CRITICAL_SECTION *dcs)
    {
        debug(PRINTF) printf("_d_criticalexit(dcs = x%x)\n", dcs);
        pthread_mutex_unlock(&dcs.cs);
    }

    extern (C) void _STI_critical_init()
    {
        if (!dcs_list)
        {
            debug(PRINTF) printf("_STI_critical_init()\n");
            pthread_mutexattr_init(&_criticals_attr);
            pthread_mutexattr_settype(&_criticals_attr, PTHREAD_MUTEX_RECURSIVE);

            // The global critical section doesn't need to be recursive
            pthread_mutex_init(&critical_section.cs, null);
            dcs_list = &critical_section;
        }
    }

    extern (C) void _STD_critical_term()
    {
        if (dcs_list)
        {
            debug(PRINTF) printf("_STI_critical_term()\n");
            while (dcs_list)
            {
                debug(PRINTF) printf("\tlooping... %x\n", dcs_list);
                pthread_mutex_destroy(&dcs_list.cs);
                dcs_list = dcs_list.next;
            }
        }
    }
}

/* ================================= NoSystem ============================ */

version( NoSystem )
{
    void _STI_critical_init() { }
    void _STD_critical_term() { }

    void _d_criticalenter(D_CRITICAL_SECTION *dcs)
    {
    }

    void _d_criticalexit(D_CRITICAL_SECTION *dcs)
    {
    }
}
