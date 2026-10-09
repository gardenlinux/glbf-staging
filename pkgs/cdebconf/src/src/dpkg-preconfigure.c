
#include "common.h"
#include "configuration.h"
#include "confmodule.h"
#include "database.h"
#include "frontend.h"
#include "question.h"
#include "template.h"

#include <getopt.h>
#include <locale.h>
#include <string.h>
#include <sys/stat.h>

#define APT_EXTRACTTEMPLATES "/usr/lib/apt/apt-extracttemplates"

struct packagename {
    char *p;
    struct packagename *next;
};

static int apt = 0;
static struct option options[] = {
    { "help", 0, NULL, 'h' },
    { "apt", 0, &apt, 'a' },
    { "frontend", 1, NULL, 'f' },
    { "priority", 1, NULL, 'p' },
    { 0, 0, 0, 0 }
};

struct package {
    char *buffer;
    const char *name;
    char *version;
    const char *templatefile;
    char *configfile;
    struct package *next;
};

static void usage(const char *exename)
{
    printf("Usage:%s [options] [debs]\n", exename);
    printf("\t--apt - Apt mode\n");
    exit(0);
}

static struct package *extract(const char *file)
{
    int pipefd[2];
    int pid;

    if (pipe(pipefd) < 0)
    {
        perror("pipe");
        return NULL;
    }

    pid = fork();
    if (pid < 0)
    {
        perror("fork");
        close(pipefd[0]);
        close(pipefd[1]);
        return NULL;
    }
    else if (pid == 0) /* child */
    {
        close(pipefd[0]);
        dup2(pipefd[1], 1);
        close(pipefd[1]);
        execlp(APT_EXTRACTTEMPLATES, APT_EXTRACTTEMPLATES, file, NULL);
        /* if we reach here, then execlp failed */
        perror("execlp");
        _exit (127);
    }
    else /* parent */
    {
        FILE *query;
        char buffer[1024];
        struct package *retval = NULL;

        close(pipefd[1]);
        
        query = fdopen(pipefd[0], "r");
        while (!feof(query))
        {
            if (fgets(buffer, 1024, query))
            {
                CHOMP(buffer);
                struct package *p = NEW(struct package);
                memset(p, 0, sizeof(*p));
                p->buffer = strdup(buffer);

                p->name = strtok(p->buffer, " \t\n");
                p->version = strtok(NULL, " \t\n");
                p->templatefile = strtok(NULL, " \t\n");
                p->configfile = strtok(NULL, " \t\n");

                if (p->configfile == NULL)
                {
                    free(p->buffer);
                    free(p);
                    retval = NULL;
                }
                else
                {
                    p->next = retval;
                    retval = p;
                }
            }
        }
        fclose(query);

        return retval;
    }
}

int main(int argc, char **argv)
{
    struct configuration *config;
    struct frontend *frontend;
    struct question_db *qdb;
    struct template_db *tdb;
    struct confmodule *confmodule;
    struct package *pkg; 
    struct packagename *pkgs = NULL;
    int c;
    
    setlocale(LC_ALL, "");
    
	if (getuid() != 0)
		DIE("%s must be run as root", argv[0]);

    config = config_new();

    while ((c = getopt_long(argc, argv, "", options, NULL)) >= 0)
    {
        switch (c)
        {
            case 'f':
                config->set(config, "_cmdline::frontend", optarg);
                break;
            case 'p':
                config->set(config, "_cmdline::priority", optarg);
                break;
            case 'h':
                usage(argv[0]);
                break;
            default:
                break;
        }
    }

    if (!apt && optind == argc)
    {
        fprintf(stderr, "dpkg-preconfigure: must specify some debs to preconfigure\n");
        exit(1);
    }

    /* parse the configuration info */
    if (config->read(config, DEBCONFCONFIG) == 0)
        DIE("Error reading configuration information");

    /* initialize database and frontend modules */
    if ((tdb = template_db_new(config, NULL)) == 0)
        DIE("Cannot initialize DebConf templates database");
    if (tdb->methods.load(tdb) != DC_OK)
        DIE("Cannot initialize debconf templates database");
    
    if ((qdb = question_db_new(config, tdb, NULL)) == 0)
        DIE("Cannot initialize DebConf configuration database");
    if (qdb->methods.load(qdb) != DC_OK)
        DIE("Cannot initialize debconf configuration database");

    if ((frontend = frontend_new(config, tdb, qdb)) == 0)
        DIE("Cannot initialize DebConf frontend");

    c = 0;
    
    if (apt) //read list of packages from stdin
    {
        int buflen = 0;
        int offset = 0;
        int bytesread = 0;
        char *buffer = NULL;
        char *file;

        do {
            buflen += 2048;
            buffer = realloc(buffer, buflen);
            bytesread = fread(buffer + offset, 1, buflen - offset, stdin);
            offset += bytesread;
        } while (bytesread == 2048);

        buffer[offset] = '\0';

        file = strtok(buffer, " \n\t");

        while (file)
        {
            struct packagename *q = NEW(struct packagename);
            if (q)
            {
                q->p = strdup(file);
                q->next = pkgs;
                pkgs = q;
                c++;
            }
            
            file = strtok(NULL, " \n\t");
        }

        free(buffer);
    }
    else
    {
        int i;
        if (optind == argc)
        {
            fputs("dpkg-preconfigure: must specify some debs to preconfigure\n", stderr);
            exit(0);
        }
        
        for (i = optind; i < argc; i++)
        {
            struct packagename *q = NEW(struct packagename);
            if (q)
            {
                q->p = strdup(argv[i]);
                q->next = pkgs;
                pkgs = q;
                c++;
            }
        }
    }

    struct packagename *pack = pkgs;
    struct package *packages = NULL;
    int packagescount = 0;

    while (pack)
    {
        struct package *p = extract(pack->p);

        if (p)
        {
            p->next = packages;
            packages = p;
            packagescount++;
            if (c > 30)
            {
                fprintf(stderr, "\rExtracting templates from packages: %d%%", 100 * packagescount / c);
            }
        }
        struct packagename *n = pack;
        pack = pack->next;
        free(n->p);
        free(n);
    }

    if (c > 30)
        fputc('\n', stderr);

    if (apt && packages)
    {
        printf("Preconfiguring packages ...\n");
    }

    for (pkg = packages; pkg != NULL; pkg = pkg->next)
    {
        template_db_loadfile(tdb, qdb, pkg->templatefile, pkg->name, DC_LOADTEMPLATE_MERGE);
        unlink(pkg->templatefile);
    }

    confmodule = confmodule_new(config, tdb, qdb, frontend);
    
    for (pkg = packages; pkg != NULL; pkg = pkg->next)
    {
        struct stat filestat;
        if (0 == stat(pkg->configfile, &filestat) && filestat.st_size > 0)
        {
            char *argvv[] = {
                NULL,
                pkg->configfile,
                "configure",
                pkg->version,
                NULL
            };
            fprintf(stderr, "preconfiguring %s (%s)\n", pkg->name, pkg->version);
            if (chmod(pkg->configfile, 0755))
            {
                DIE("debconf: can't chmod: \n");
            }
            confmodule->owner = pkg->name;
            frontend->methods.set_title(frontend, pkg->name);
            confmodule->run(confmodule, 4, argvv);
            if (DC_OK != confmodule->communicate(confmodule))
            {
                fprintf(stderr, "%s failed to preconfigure, with exit status %s\n", pkg->name, "");
            }
        }
        unlink(pkg->configfile);
    }

    confmodule->shutdown(confmodule);

    confmodule->save(confmodule);
    confmodule_delete(confmodule);

    return 0;
}
