require('ggplot2')
require('nls.multstart')
require('broom')
require('tidyverse')
require('rTPC')
require('dplyr')
require('data.table')
require('car')
require('boot')
require('patchwork')
require('minpack.lm')
require("tidyr")
require('purrr')
# update.packages(ask = FALSE)

rm(list=ls())
graphics.off()
setwd("/home/primuser/Documents/VByte/VecMismatchPaper1/code/")

#take a look at the different models available
get_model_names()

#read in the trait data
final_trait_data <- read.csv('../data/Final_Traitofinterest.csv')

#filter out sets that less than the required parameters for schoolfield-high ()

# final_trait_data <- dplyr::filter(final_trait_data,
#                                   originaltraitname != 'Adult survival' &
#                                     originalid != 'MSS0059' &
#                                     originaltraitname != 'Adult longevity (female, bloodfed)' &
#                                     originaltraitname != 'Adult longevity (male)' &
#                                     originaltraitname != 'Adult survival (female, bloodfed)' &
#                                     originaltraitname != 'Adult survival (male)' )


#remove completely irrelevant columns 
df <- final_trait_data[,colSums(is.na(final_trait_data))<nrow(final_trait_data)]

#filter to single species and trait
df2 <- dplyr::filter(df, originalid == 'csm7I')

#add example root
# exam <- data.frame('csm7I', 'Development Rate', '1/day', 1*10^-6, 'Tetranychus mcdanieli', 40)
# names(exam) <- c('originalid', 'originaltraitname', 'originaltraitunit', 'rate', 'interactor1', 'temp')
# df2 <- rbind(df2, exam)


df1 <- df %>%
  select('originalid', 'originaltraitname', 'originaltraitunit', 'originaltraitvalue', 'interactor1', 'ambienttemp', 'citation')



#visualize
ggplot(df2, aes(ambienttemp, originaltraitvalue))+
  geom_point()+
  theme_bw(base_size = 12) +
  labs(x = 'Temperature (ºC)',
       y = 'Development Rate',
       title = 'Development Rate across temperatures for Aedes albopictus')


#filter to single species and trait
df2 <- dplyr::filter(df, originalid == 'csm7I')

df1 <- df %>%
  dplyr::select('originalid', 'originaltraitname', 'originaltraitunit', 'originaltraitvalue', 'interactor1', 'ambienttemp', 'citation')
#filter to single species and trait
df2 <- dplyr::filter(df1, originalid == 'csm7I')

#visualize
ggplot(df2, aes(ambienttemp, originaltraitvalue))+
  geom_point()+
  theme_bw(base_size = 12) +
  labs(x = 'Temperature (ºC)',
       y = 'Development Rate',
       title = 'Development Rate across temperatures for Aedes albopictus')

# choose model
mod = 'sharpschoolhigh_1981'
#mutate the titles because I am lazy and I don't want to change the formula
d<- df2 %>%
  rename(temp = ambienttemp,
         rate = originaltraitvalue)

#add example root
# exam <- data.frame('csm7I', 'Development Rate', '1/day', 1*10^-6, 'Tetranychus mcdanieli', 40)
# names(exam) <- c('originalid', 'originaltraitname', 'originaltraitunit', 'rate', 'interactor1', 'temp')
# d <- rbind(d, exam)

# fit Sharpe-Schoolfield model
d_fit <- nest(d, data = c(temp, rate)) %>%
  mutate(sharpeschoolhigh = map(data, ~nls_multstart(rate~sharpeschoolhigh_1981(temp = temp, r_tref,e,eh,th, tref = 15),
                                                     data = .x,
                                                     iter = c(3,3,3,3),
                                                     start_lower = get_start_vals(.x$temp, .x$rate, model_name = 'sharpeschoolhigh_1981') - 10,
                                                     start_upper = get_start_vals(.x$temp, .x$rate, model_name = 'sharpeschoolhigh_1981') + 10,
                                                     lower = get_lower_lims(.x$temp, .x$rate, model_name = 'sharpeschoolhigh_1981'),
                                                     upper = get_upper_lims(.x$temp, .x$rate, model_name = 'sharpeschoolhigh_1981'),
                                                     supp_errors = 'Y',
                                                     convergence_count = FALSE)),
         
         # create new temperature data
         new_data = map(data, ~tibble(temp = seq(min(.x$temp), max(.x$temp), length.out = 100))),
         # predict over that data,
         preds =  map2(sharpeschoolhigh, new_data, ~augment(.x, newdata = .y)))


# unnest predictions
d_preds <- select(d_fit, preds) %>%
  unnest(preds)

# plot data and predictions
ggplot() +
  geom_line(aes(temp, .fitted), d_preds, col = 'blue') +
  geom_point(aes(temp, rate), d, size = 2, alpha = 0.5) +
  theme_bw(base_size = 12) +
  labs(x = 'Temperature (ºC)',
       y = 'Growth rate',
       title = 'Growth rate across temperatures')


# refit model using nlsLM
fit_nlsLM <- minpack.lm::nlsLM(rate~sharpeschoolhigh_1981(temp = temp, r_tref,e,eh,th, tref = 15),
                               data = d,
                               start = coef(d_fit$sharpeschoolhigh[[1]]),
                               lower = get_lower_lims(d$temp, d$rate, model_name = 'sharpeschoolhigh_1981'),
                               upper = get_upper_lims(d$temp, d$rate, model_name = 'sharpeschoolhigh_1981'),
                               weights = rep(1, times = nrow(d)))

# bootstrap using case resampling
boot1 <- Boot(fit_nlsLM, method = 'case')

# look at the data
head(boot1$t)


hist(boot1, layout = c(2,2))


# create predictions of each bootstrapped model
boot1_preds <- boot1$t %>%
  as.data.frame() %>%
  drop_na() %>%
  mutate(iter = 1:n()) %>%
  group_by_all() %>%
  do(data.frame(temp = seq(min(d$temp), max(d$temp), length.out = 100))) %>%
  ungroup() %>%
  mutate(pred = sharpeschoolhigh_1981(temp, r_tref, e, eh, th, tref = 15))

# calculate bootstrapped confidence intervals
boot1_conf_preds <- group_by(boot1_preds, temp) %>%
  summarise(conf_lower = quantile(pred, 0.025),
            conf_upper = quantile(pred, 0.975)) %>%
  ungroup()

# plot bootstrapped CIs
p1 <- ggplot() +
  geom_line(aes(temp, .fitted), d_preds, col = 'blue') +
  geom_ribbon(aes(temp, ymin = conf_lower, ymax = conf_upper), boot1_conf_preds, fill = 'blue', alpha = 0.3) +
  geom_point(aes(temp, rate), d, size = 2, alpha = 0.5) +
  theme_bw(base_size = 12) +
  labs(x = 'Temperature (ºC)',
       y = 'Growth rate',
       title = 'Growth rate across temperatures')

# plot bootstrapped predictions
p2 <- ggplot() +
  geom_line(aes(temp, .fitted), d_preds, col = 'blue') +
  geom_line(aes(temp, pred, group = iter), boot1_preds, col = 'blue', alpha = 0.007) +
  geom_point(aes(temp, rate), d, size = 2, alpha = 0.5) +
  theme_bw(base_size = 12) +
  labs(x = 'Temperature (ºC)',
       y = 'Growth rate',
       title = 'Growth rate across temperatures')


p1 + p2


d<- df1 %>%
  rename(temp = ambienttemp,
         rate = originaltraitvalue)

#invert data as needed for inverse schoolfield
d <-mutate(d, inversetraitvalue = 1/rate)


#change heading to correct variable
d <-  mutate(d, adjustedtraitname = ifelse(originaltraitname == 'Mortality Rate' , 'zj',
                                                              ifelse(originaltraitname == 'Egg development time' , 'a',
                                                                     ifelse(originaltraitname == 'Generation Time' , 'a',
                                                                            ifelse(originaltraitname == 'Survival Rate' , 'z',
                                                                                   ifelse(originaltraitname == 'Development time' , 'a',
                                                                                          ifelse(originaltraitname == 'Development Time' , 'a',
                                                                                                 ifelse(originaltraitname == 'Development Rate' , 'a',
                                                                                                        ifelse(originaltraitname == 'Survivorship' , 'z',
                                                                                                               ifelse(originaltraitname == 'Longevity' , 'z',
                                                                                                                      ifelse(originaltraitname == 'Survival Time' , 'z',
                                                                                                                             ifelse(originaltraitname == 'Percentage Survival' , 'z',
                                                                                                                                    ifelse(originaltraitname == 'Oviposition Rate' , 'bpk',
                                                                                                                                           ifelse(originaltraitname == 'Juvenile survival ' , 'zj',
                                                                                                                                                  ifelse(originaltraitname == 'Fecundity Rate' , 'k',
                                                                                                                                                         ifelse(originaltraitname == 'Fecundity' , 'k',
                                                                                                                                                                originaltraitname))))))))))))))))





#concatenate to get curves
d$cit <- gsub("([A-Za-z]+).*", "\\1", d$citation)
d$conc <- paste(d$interactor1, "_", d$originaltraitname, "_", d$cit)
d$conc <- as.character(d$conc)
d$conc <- gsub(" ", "", d$conc, fixed = TRUE)
numberofcurves <- unique(d$conc)

#plot to check
ggplot(data = d, aes(temp, rate))+
  geom_point()+
  theme_bw(base_size = 12) +
  labs(x = 'Temperature (ºC)',
       y = 'Trait Data')+
  facet_wrap(~d$conc, scale ='free')

#loop time
# fit Sharpe-Schoolfield model

d_fit <- list()
d_preds <- list()
fit_nlsLM <- list()
boot1 <- list()
boot1_preds <- list()
boot1_conf_preds <- list()
for (x in unique(d$conc)){
d_fit <- nest(d[[x]], data = c(temp, rate)) %>%
  mutate(sharpeschoolhigh = map(data, ~nls_multstart(rate~sharpeschoolhigh_1981(temp = temp, r_tref,e,eh,th, tref = 15),
                                                     data = .x,
                                                     iter = c(3,3,3,3),
                                                     start_lower = get_start_vals(.x$temp, .x$rate, model_name = 'sharpeschoolhigh_1981') - 10,
                                                     start_upper = get_start_vals(.x$temp, .x$rate, model_name = 'sharpeschoolhigh_1981') + 10,
                                                     lower = get_lower_lims(.x$temp, .x$rate, model_name = 'sharpeschoolhigh_1981'),
                                                     upper = get_upper_lims(.x$temp, .x$rate, model_name = 'sharpeschoolhigh_1981'),
                                                     supp_errors = 'Y',
                                                     convergence_count = FALSE)),

         # create new temperature data
         new_data = map(data, ~tibble(temp = seq(min(.x$temp), max(.x$temp), length.out = 100))),
         # predict over that data,
         preds =  map2(sharpeschoolhigh, new_data, ~augment(.x, newdata = .y)))


# unnest predictions
d_preds[[x]] <- select(d_fit, preds) %>%
  unnest(preds)

# refit model using nlsLM
fit_nlsLM[[x]] <- minpack.lm::nlsLM(rate~sharpeschoolhigh_1981(temp = temp, r_tref,e,eh,th, tref = 15),
                               data = d[[x]],
                               start = coef(d_fit$sharpeschoolhigh[[1]]),
                               lower = get_lower_lims(d$temp, d$rate, model_name = 'sharpeschoolhigh_1981'),
                               upper = get_upper_lims(d$temp, d$rate, model_name = 'sharpeschoolhigh_1981'),
                               weights = rep(1, times = nrow(d)))

# bootstrap using case resampling
boot1[[x]] <- Boot(fit_nlsLM, method = 'case')


# create predictions of each bootstrapped model
boot1_preds[[x]] <- boot1$t %>%
  as.data.frame() %>%
  drop_na() %>%
  mutate(iter = 1:n()) %>%
  group_by_all() %>%
  do(data.frame(temp = seq(min(d$temp), max(d$temp), length.out = 100))) %>%
  ungroup() %>%
  mutate(pred = sharpeschoolhigh_1981(temp, r_tref, e, eh, th, tref = 15))

# calculate bootstrapped confidence intervals
boot1_conf_preds[[x]] <- group_by(boot1_preds, temp) %>%
  summarise(conf_lower = quantile(pred, 0.025),
            conf_upper = quantile(pred, 0.975)) %>%
  ungroup()


}

