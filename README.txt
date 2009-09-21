NAME
    SimplenoteSync.pl - synchronize a folder of text files with Simplenote.

    Of note, this software is not created by or endorsed by Cloud Factory,
    the creators of Simplenote, or anyone else for that matter.

CONFIGURATION
    BACKUP YOUR DATA BEFORE USING --- THIS PROJECT IS STILL BEING TESTED. IF
    YOU AREN'T CONFIDENT IN WHAT YOU'RE DOING, DON'T USE IT!!!!

    Create file in your home directory named ".simplenotesyncrc" with the
    following contents:

    1. First line is your email address

    2. Second line is your Simplenote password

    3. Third line is the directory to be used for text files

    Unfortunately, you have to install Crypt::SSLeay to get https to work.
    You can do this by running the following command as an administrator:

    sudo perl -MCPAN -e "install Crypt::SSLeay"

DESCRIPTION
    After specifying a folder to store local text files, and the email
    address and password associated with your Simplenote account,
    SimplenoteSync will attempt to synchronize the information in both
    places.

    Sync information is stored in "simplenotesync.db". If this file is lost,
    SimplenoteSync will have to attempt to look for "collisions" between
    local files and existing notes. When performing the first
    synchronization, it's best to start with an empty local folder (or an
    empty collection of notes on Simplenote), and then start adding files
    (or notes) afterwards.

WARNING
    Please note that this software is still in development stages - I
    STRONGLY urge you to backup all of your data before running to ensure
    nothing is lost. If you run SimplenoteSync on an empty local folder
    without a "simplenotesync.db" file, the net result will be to copy the
    remote notes to the local folder, effectively performing a backup.

FAQ
    * Why can I download notes from Simplenote, but local notes aren't being
    uploaded?

    Do the text files end in ".txt"? For documents to be recognized as text
    files to be uploaded, they have to have that file extension.

    Text files can't be located in subdirectories - this script does not (by
    design) recurse folders looking for files (since they shouldn't be
    anywhere but the specified directory).

    * When my note is downloaded from Simplenote and then changed locally, I
    end up with two copies of the first line (one shorter than the other) -
    what gives?

    If the first line of a note is too long to become the filename, it is
    trimmed to an appropriate length. To prevent losing data, the full line
    is preserved in the body. Since Simplenote doesn't have a concept of
    titles, the title becomes the first line (which is trimmed), and the
    original first line is now the third line (counting the blank line in
    between). Your only alternatives are to shorten the first line, split it
    in two, or to create a short title

TROUBLESHOOTING
    If SimplenoteSync isn't working, I've tried to add more (and better)
    error messages. Common problems so far include:

    * Not installing Crypt::SSLeay

    * Errors in the "simplenotesyncrc" file

    Optionally, you can enable or disable writing changes to either the
    local directory or to the Simplenote web server. For example, if you
    want to attempt to copy files to your computer without risking your
    remote data, you can disable "$allow_server_updates". Or, you can
    disable "$allow_local_updates" to protect your local data.

KNOWN ISSUES
    * No merging when both local and remote file are changed between syncs -
    this is planned for the future

    * the code is still somewhat ugly

    * it's probably not very efficient and might really bog down with large
    numbers of notes

    * renaming notes or text files causes it to be treated as a new note -
    probably not all bad, but not sure what else to do

    * No two notes can share the same title (in this event, only one will be
    downloaded locally, the others will trigger a warning at each sync)

SEE ALSO
    Designed for use with Simplenote for iPhone:

    <http://www.simplenoteapp.com/>

    The SimplenoteSync homepage is:

    <http://fletcherpenney.net/other_projects/simplenotesync/>

    SimplenoteSync is available on github:

    <http://github.com/fletcher/SimplenoteSync>

AUTHOR
    Fletcher T. Penney, <owner@fletcherpenney.net>

COPYRIGHT AND LICENSE
    Copyright (C) 2009 by Fletcher T. Penney

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the
    Free Software Foundation; either version 2 of the License, or (at your
    option) any later version.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
    Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.
    59 Temple Place, Suite 330 Boston, MA 02111-1307 USA

