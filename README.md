# dotfiles

## Installing

Run the following in your terminal:

```bash 
bash -c "$(curl -L https://raw.githubusercontent.com/kyle-angus/dotfiles/master/install.sh)"
```

## Modifying

I've added a Dockerfile which builds an uniminimized ubuntu server image which can be used
for testing changes in a "clean" environment.

The docker image can be built from the repo root directory with: 


```bash
docker build -t <name_of_image> .
```

...and can be run with: 

```bash
docker run -it <name_of_image>
```

The default password for the `kangus` user is: `Test123`

## TODO

- [ ] Document scripts
- [ ] Document tmux config
- [ ] Document irssi config
- [ ] Document vim config
- [ ] Add flag to uninstall/remove changes as a result of running the install script
- [ ] Get rid of coc.nvim and use native lsp