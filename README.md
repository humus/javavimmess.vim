# The javavimmess

## What is javavimmess.vim

javavimmess is a whole pile of functions, mappings and commands created to
ease and speed up the development for java projects directly by using the vim
editor. Along with the purpose of speedup the development in java projects it
uses raw javac and java commands to make the Red-Green-Refactor cycles lighter
than with any IDE or build tool out there

## What is not

This plugin is not a dependency manager for your build, is not an IDE and not
a build tool this plugin is just a bunch of (by opinion of the author) most
needed features for smoother development for the java platform

## What currently does

In the current states of the project, It provides mappings for going (by
conventions) to The unit test of the class you are editting and Vice-versa and
provide you with commands for Index the whole bunch of jars that your build
tool uses (currently only maven) and all the classes that are contained in
those jar files for resolving imports.

Once created the cache and Indexed the classes you can turn on the feature of
compile on save and if the current buffer is a JUnit test, you can execute it
just by calling the *:Junit* command

Now the plugin has a set of mappings and functions to make simple autocomplete
work by using the javap command to get a list of public methods and class
members. The autocomplete works by common conventions while developing java
code so, most of the time the plugin can know if you want to complete a class
or a instance member

###Commands
##### CacheCurrProjMaven
When executed it parse the class path provided by maven and copies all the
jars to a directory named *.cache* in the directory where the build tool file
resides


#### IndexCache
Once the *.cache* directory is created and contains all the jars in the
classpath generated by the build tool, this command creates and sorts a text
file which contains the Name and the fully quallified class name of all the
classes contained in the jars which are inside of the *.cache* directory

#### CreateIndex
This command is just the combination of the *CacheCurrProjMaven* and
*IndexCache* commands

#### CompileOnSaveToggle
When executed for the first time in the current buffer it turns on the setting
for compile the current file when saved. Successive executions of this command
will toggle the setting on and off

### Javac
Compiles the file that correspond to the current buffer

### Junit
Executes the current class as a JUnit test

## License
Distributed under the sames terms as Vim itself. See `:help License`
