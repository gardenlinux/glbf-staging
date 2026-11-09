package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"

	diskfs "github.com/diskfs/go-diskfs"
	"github.com/diskfs/go-diskfs/disk"
	"github.com/diskfs/go-diskfs/filesystem"
)

const fatEpoch = 315532800

func fail(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "mkfat32: "+format+"\n", a...)
	os.Exit(1)
}

func main() {
	dir := flag.String("d", "", "directory tree to populate the filesystem from")
	flag.Parse()

	if flag.NArg() != 1 {
		fail("usage: mkfat32 [-d <dir>] <img>")
	}
	img := flag.Arg(0)

	epoch := int64(0)
	if v := os.Getenv("MKFAT32_FAKE_TIME"); v != "" {
		n, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			fail("invalid MKFAT32_FAKE_TIME %q: %v", v, err)
		}
		epoch = n
	}
	if epoch < fatEpoch {
		epoch = fatEpoch
	}
	if err := os.Setenv("SOURCE_DATE_EPOCH", strconv.FormatInt(epoch, 10)); err != nil {
		fail("setenv: %v", err)
	}

	d, err := diskfs.Open(img, diskfs.WithOpenMode(diskfs.ReadWrite))
	if err != nil {
		fail("open %s: %v", img, err)
	}
	defer d.Close()

	fs, err := d.CreateFilesystem(disk.FilesystemSpec{
		Partition:    0,
		FSType:       filesystem.TypeFat32,
		Reproducible: true,
	})
	if err != nil {
		fail("create filesystem: %v", err)
	}

	if *dir != "" {
		if err := populate(fs, *dir); err != nil {
			fail("populate: %v", err)
		}
	}
}

func populate(fs filesystem.FileSystem, src string) error {
	type node struct {
		rel string
		dir bool
	}
	var nodes []node

	err := filepath.WalkDir(src, func(path string, de os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		nodes = append(nodes, node{rel: filepath.ToSlash(rel), dir: de.IsDir()})
		return nil
	})
	if err != nil {
		return err
	}

	sort.Slice(nodes, func(i, j int) bool { return nodes[i].rel < nodes[j].rel })

	for _, n := range nodes {
		dst := "/" + n.rel
		if n.dir {
			if err := fs.Mkdir(dst); err != nil {
				return fmt.Errorf("mkdir %s: %w", dst, err)
			}
			continue
		}
		if err := copyFile(fs, filepath.Join(src, filepath.FromSlash(n.rel)), dst); err != nil {
			return err
		}
	}
	return nil
}

func copyFile(fs filesystem.FileSystem, hostPath, dst string) error {
	in, err := os.Open(hostPath)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := fs.OpenFile(dst, os.O_CREATE|os.O_RDWR)
	if err != nil {
		return fmt.Errorf("open %s: %w", dst, err)
	}
	if _, err := io.Copy(out, in); err != nil {
		return fmt.Errorf("copy %s: %w", dst, err)
	}
	if c, ok := out.(io.Closer); ok {
		if err := c.Close(); err != nil {
			return fmt.Errorf("close %s: %w", dst, err)
		}
	}
	return nil
}
